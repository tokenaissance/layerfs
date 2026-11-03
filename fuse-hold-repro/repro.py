#!/usr/bin/env python3
"""FUSE: a detached mount whose superblock another mount namespace still holds
keeps its readers blocked. Self-contained: no libfuse, only /dev/fuse + mount(2).

Run as root with CAP_SYS_ADMIN and /dev/fuse:
  docker run --rm --cap-add SYS_ADMIN --device /dev/fuse \
      --security-opt apparmor=unconfined -v "$PWD":/src -w /src \
      python:3.12-slim python3 repro.py

What it does:
  1. mounts a bare FUSE filesystem at /tmp/fuse-hold-mnt in this namespace;
  2. forks a holder that unshares a second mount namespace and keeps that
     mount (same superblock) while it sleeps;
  3. unmounts in the first namespace: umount2 returns 0, mountinfo loses the
     mount, but two read(/dev/fuse) threads stay blocked;
  4. after a grace period writes "1" to /sys/fs/fuse/connections/<minor>/abort
     and shows the readers wake. --abort-at-deadline mimics the daemon's
     abort-on-Join (#496); --grace N sets the join observation window (#497).
"""
import argparse, ctypes, os, re, signal, struct, sys, threading, time

libc = ctypes.CDLL("libc.so.6", use_errno=True)
CLONE_NEWNS = 0x00020000
MS_REC, MS_PRIVATE = 1 << 14, 1 << 18
MNT_DETACH = 2
FUSE_INIT = 26
FUSE_KERNEL_VERSION = 7
FUSE_KERNEL_MINOR_VERSION = 31
MNT = "/tmp/fuse-hold-mnt"


def mount(source, target, fstype, flags, data):
    r = libc.mount(source.encode(), target.encode(), fstype.encode(), ctypes.c_ulong(flags), data.encode() if data else None)
    if r != 0:
        raise OSError(ctypes.get_errno(), f"mount({target})")


def umount2(target, flags):
    r = libc.umount2(target.encode(), ctypes.c_int(flags))
    return r, ctypes.get_errno()


def unshare(flags):
    if libc.unshare(ctypes.c_int(flags)) != 0:
        raise OSError(ctypes.get_errno(), "unshare(CLONE_NEWNS)")


def mount_private_root():
    if libc.mount(b"none", b"/", None, ctypes.c_ulong(MS_REC | MS_PRIVATE), None) != 0:
        raise OSError(ctypes.get_errno(), "make-rprivate /")


def minor_of(mnt):
    with open("/proc/self/mountinfo", encoding="utf-8") as f:
        for line in f:
            fields = line.split()
            if len(fields) > 4 and fields[4] == mnt:
                return int(fields[2].split(":")[1])
    return None


def in_mountinfo(mnt):
    with open("/proc/self/mountinfo", encoding="utf-8") as f:
        return any(len(l.split()) > 4 and l.split()[4] == mnt for l in f)


def reply_init(fd):
    """Consume FUSE_INIT and answer it, so later reads are request reads."""
    data = os.read(fd, 1 << 20)
    if len(data) < 40:
        return False
    length, opcode, unique = struct.unpack_from("<IIQ", data, 0)
    if opcode != FUSE_INIT:
        return False
    init = struct.pack("<IIII", FUSE_KERNEL_VERSION, FUSE_KERNEL_MINOR_VERSION, 0, 0)
    out = struct.pack("<IIQ", 16 + 64, 0, unique) + init + struct.pack(
        "<HHIIHHI", 0, 0, 4096, 1, 1, 0, 0) + b"\0" * 28
    os.write(fd, out)
    return True


def reader(fd, name, state, lock, wake):
    try:
        r = os.read(fd, 1 << 20)
        with lock:
            state[name] = "returned" if r else "eof"
            wake.set()
    except OSError as e:
        with lock:
            state[name] = f"error {e.errno}"
            wake.set()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--grace", type=float, default=2.0, help="join observation window (s)")
    ap.add_argument("--abort-at-deadline", action="store_true", help="write fusectl abort when the grace ends (#496)")
    args = ap.parse_args()

    os.makedirs(MNT, exist_ok=True)
    mount_private_root()
    fd = os.open("/dev/fuse", os.O_RDWR)
    data = f"fd={fd},rootmode=40000,user_id={os.getuid()},group_id={os.getgid()}"
    mount("fuse", MNT, "fuse", 0, data)
    minor = minor_of(MNT)
    print(f"mounted {MNT} (fusectl minor {minor})")
    reply_init(fd)

    pid = os.fork()
    if pid == 0:
        try:
            unshare(CLONE_NEWNS)
            mount_private_root()
            time.sleep(3600)
        finally:
            os._exit(0)
    time.sleep(0.3)
    print(f"holder pid {pid} in a second mount namespace still holds the superblock")

    lock, wake, state = threading.Lock(), threading.Event(), {}
    threads = [threading.Thread(target=reader, args=(fd, n, state, lock, wake), daemon=True) for n in ("r1", "r2")]
    for t in threads:
        t.start()
    time.sleep(0.3)

    before = in_mountinfo(MNT)
    rc, err = umount2(MNT, 0)
    print(f"umount2({MNT}, 0) -> rc={rc} errno={err}; mountinfo had it={before}, has it now={in_mountinfo(MNT)}")

    woke = wake.wait(args.grace)
    with lock:
        print(f"after {args.grace:.1f}s grace: readers={state or {'r1': 'blocked', 'r2': 'blocked'}} (woke={woke})")

    if not woke:
        if args.abort_at_deadline:
            path = f"/sys/fs/fuse/connections/{minor}/abort"
            try:
                try:
                    with open(path, "w") as f:
                        f.write("1")
                except FileNotFoundError:
                    if libc.mount(b"fusectl", b"/sys/fs/fuse/connections", b"fusectl", ctypes.c_ulong(0), None) != 0:
                        raise OSError(ctypes.get_errno(), "mount fusectl")
                    with open(path, "w") as f:
                        f.write("1")
                print(f"wrote 1 to {path} (abort-on-Join, #496)")
            except OSError as e:
                print(f"cannot write {path}: {e} (mount fusectl first: mount -t fusectl none /sys/fs/fuse/connections)")
        else:
            path = f"/sys/fs/fuse/connections/{minor}/abort"
            print(f"readers still blocked; positive control: echo 1 > {path}")
        wake.wait(3)

    with lock:
        print("final reader state:", state)
    os.kill(pid, signal.SIGKILL)
    try:
        os.rmdir(MNT)
    except OSError:
        pass


if __name__ == "__main__":
    main()
