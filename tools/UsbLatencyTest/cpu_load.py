"""Keeps N processes busy for S seconds, then exits: python cpu_load.py N S"""

import multiprocessing
import sys
import time


def spin(seconds):
    end = time.perf_counter() + seconds
    while time.perf_counter() < end:
        pass


if __name__ == "__main__":
    n_processes, seconds = int(sys.argv[1]), float(sys.argv[2])
    processes = [multiprocessing.Process(target=spin, args=(seconds,)) for _ in range(n_processes)]
    for process in processes:
        process.start()
    for process in processes:
        process.join()
