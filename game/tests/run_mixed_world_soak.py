"""Run the eight-client T090 workload on an isolated copy of the game."""

import argparse
import collections
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import statistics
import subprocess
import time

import psutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--seconds", type=float, default=28800)
    parser.add_argument("--reconnect-every", type=float, default=600)
    parser.add_argument("--host-max-fps", type=int, default=60, help="Cap the dedicated host for a 10-second timing diagnostic after warmup")
    args = parser.parse_args()
    if args.seconds < 120 or not 10 <= args.reconnect_every <= args.seconds - 25:
        parser.error("allow at least 120 seconds and time for a staggered reconnect")
    if args.host_max_fps < 1:
        parser.error("the host frame rate must be positive")

    args.output = args.output.resolve()
    args.engine = args.engine.resolve(strict=True)
    args.output.mkdir(parents=True)
    run(args)


def run(args):
    output = args.output
    armed = []
    source = Path(__file__).resolve().parents[1]
    project = output / "project"
    shutil.copytree(source, project, ignore=shutil.ignore_patterns("work", "docs", "editor", "shader_cache", "services", "deploy", "__pycache__", ".git"))
    digest = hashlib.sha256()
    for path in sorted((project / "scripts").glob("*.gd")):
        digest.update(path.name.encode())
        digest.update(path.read_bytes())
    digest.update((project / "tests/mixed_world_soak.gd").read_bytes())
    identity = {"duration":args.seconds, "reconnect_every":args.reconnect_every, "host_max_fps":args.host_max_fps,
                "script_sha256":digest.hexdigest(), "release":json.loads((project / "release.json").read_text(encoding="utf-8"))}
    (output / "configuration.json").write_text(json.dumps(identity, indent=2), encoding="utf-8")
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]

    def start(name, mode, *extra):
        user_dir = output / name
        user_dir.mkdir()
        env = {key: value for key, value in os.environ.items() if not key.upper().startswith("GAME_")}
        env.update({key: str(user_dir) for key in ("APPDATA", "LOCALAPPDATA", "TEMP", "TMP", "XDG_DATA_HOME")})
        fps = 20 if mode == "client" else 60
        command = [str(args.engine), "--headless", "--path", str(project), "--max-fps", str(fps),
                   "--script", "res://tests/mixed_world_soak.gd", "--", mode, output.as_posix(), str(port), *map(str, extra)]
        path = user_dir / "runtime.log"
        with path.open("wb") as log:
            child = subprocess.Popen(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        armed.append((child, path))
        return child, path

    def check_exit(child, path, timeout):
        if child.wait(timeout) != 0:
            raise RuntimeError(f"process {child.pid} failed, see {path}")

    try:
        check_exit(*start("seed", "seed"), 30)
        initial_world_time = json.loads((output / "world.json").read_text(encoding="utf-8"))["time"]
        host, host_log = start("server", "server", args.host_max_fps)
        wait_until(lambda: "SERVER_READY" in host_log.read_text(encoding="utf-8", errors="replace"), [host], 20)
        clients = [start(f"client-{index}", "client", index, args.seconds, args.reconnect_every) for index in range(1, 9)]
        wait_until(lambda: len(list(output.glob("ready-*.json"))) == 8, [host, *(client for client, _ in clients)], 30)
        (output / "start").touch()
        print(f"SOAK_STARTED server={host.pid} clients={[client.pid for client, _ in clients]} duration={args.seconds:g}", flush=True)
        telemetry = Telemetry(host, clients)
        try:
            measure(output, host, clients, args.seconds, telemetry)
            for client, path in clients:
                check_exit(client, path, 15)
        except RuntimeError as error:
            # Snapshot first: which clients had already failed and what the machine looked like at the timeout.
            try:
                at_failure = telemetry.snapshot()
            except Exception as snapshot_error:  # never let telemetry hide the original failure
                at_failure = {"processes": {}, "snapshot_error": repr(snapshot_error)}
            # Allow other peers to record the same outage before teardown kills them.
            time.sleep(1.5)
            report = failure_evidence(error, host, host_log, clients)
            report["telemetry_at_failure"] = at_failure
            report["failed_clients_at_detection"] = sorted(
                (name for name, entry in at_failure["processes"].items() if entry["exit_code"] not in (None, 0)))
            report["failure_order"] = failure_order(report["clients"])
            (output / "failure.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
            raise
        (output / "stop").touch()
        check_exit(host, host_log, 15)
        check_exit(*start("verify", "verify"), 30)
        for _, path in armed:
            with path.open(encoding="utf-8", errors="replace") as log:
                if any(line.startswith(("ERROR:", "SCRIPT ERROR:")) for line in log):
                    raise RuntimeError(f"game errors in {path}")
        result = json.loads((output / "verified.json").read_text(encoding="utf-8"))
        result["world_seconds_advanced"] = result["world_seconds"] - initial_world_time
        if result["world_seconds_advanced"] < args.seconds * 0.9:
            raise RuntimeError("world clock advanced less than 90 percent of the measured time")
        result["clients"] = [json.loads((output / f"result-{i}.json").read_text(encoding="utf-8")) for i in range(1, 9)]
        minimum_reconnects = max(1, int((args.seconds - 25) / args.reconnect_every))
        for client in result["clients"]:
            if client["seconds"] < args.seconds or client["rounds"] < int(args.seconds / 15) or client["reconnects"] < minimum_reconnects:
                raise RuntimeError("a client did not sustain the requested workload")
            if client["keyframes"] < client["reconnects"] + 1 or client["delta_frames"] <= client["keyframes"]:
                raise RuntimeError("a client did not sustain delta snapshots across reconnects")
        result["measurements"] = summarize(output / "samples.csv")
        (output / "complete.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
        print("SOAK_COMPLETE", json.dumps(result), flush=True)
    finally:
        # Stop only subprocess trees created for this run.
        teardown = {"started_unix": time.time(), "processes": []}
        for child, path in armed:
            entry = {"name": path.parent.name, "pid": child.pid, "exit_code_before": child.poll()}
            teardown["processes"].append(entry)
            if entry["exit_code_before"] is not None:
                continue
            entry["terminate_unix"] = time.time()
            try:
                for process in reversed(psutil.Process(child.pid).children(recursive=True)):
                    try:
                        process.terminate()
                    except psutil.NoSuchProcess:
                        pass
                child.terminate()
            except psutil.NoSuchProcess:
                pass
            try:
                child.wait(10)
            finally:
                entry["exit_unix"] = time.time()
                entry["exit_code_after"] = child.poll()
                write_teardown(output, teardown)
        write_teardown(output, teardown)


def write_teardown(output, teardown):
    try:
        (output / "teardown.json").write_text(json.dumps(teardown, indent=2), encoding="utf-8")
    except OSError:
        pass


def wait_until(condition, processes, seconds):
    deadline = time.monotonic() + seconds
    while not condition():
        if time.monotonic() >= deadline or any(process.poll() is not None for process in processes):
            raise RuntimeError("a process stopped or startup timed out")
        time.sleep(0.25)


def failure_evidence(error, host, host_log, clients):
    def snapshot(process, log, prefixes):
        with log.open(encoding="utf-8", errors="replace") as lines:
            matched = [line.strip() for line in lines if line.startswith(prefixes)]
        return {"exit_code": process.poll(), "last_events": matched[-8:]}

    def peers(log):
        # Numeric peer ids only; correlates client N with the server's connected/disconnected peer lines.
        with log.open(encoding="utf-8", errors="replace") as lines:
            return [line.strip() for line in lines if line.startswith("SOAK_PEER ")][-8:]

    report = {
        "reason": str(error),
        "unix": time.time(),
        "diagnostics_captured_before_teardown": True,
        "teardown_started": False,
        "host": snapshot(host, host_log, ("SOAK_SERVER_", "ERROR:", "SCRIPT ERROR:")),
        "clients": {},
    }
    report["host"]["timing"] = snapshot(host, host_log, ("SERVER_T090 ",))["last_events"]
    report["host"]["movement_inputs"] = snapshot(host, host_log, ("SERVER_T090_INPUT ",))["last_events"]
    for index, (client, log) in enumerate(clients, 1):
        entry = snapshot(client, log, ("SOAK_DISCONNECT", "SOAK_CLIENT_EXIT", "SOAK_WALK_DIAG", "ERROR:", "SCRIPT ERROR:"))
        entry["peers"] = peers(log)
        report["clients"][str(index)] = entry
    return report


class Telemetry:
    """Small ring of runner samples plus a one-shot machine snapshot taken when a failure is detected."""

    def __init__(self, host, clients):
        self.targets = {"server": host, **{f"client-{i}": child for i, (child, _) in enumerate(clients, 1)}}
        self.procs = {}
        self.ring = collections.deque(maxlen=12)
        self.sample_cost_ms = 0.0
        self.last = None
        psutil.cpu_percent(percpu=True)  # prime: later calls report the interval since the previous sample

    def process(self, name):
        if name not in self.procs:
            self.procs[name] = psutil.Process(self.targets[name].pid)
        return self.procs[name]

    def read(self, name):
        # Windows' console executable launches the engine as a child process.
        try:
            launcher = self.process(name)
            processes = [launcher, *launcher.children(recursive=True)]
        except (psutil.Error, OSError):
            return None
        samples = []
        for process in processes:
            try:
                with process.oneshot():
                    times = process.cpu_times()
                    samples.append({
                        "pid": process.pid, "name": process.name(), "cpu_seconds": times.user + times.system,
                        "rss_bytes": process.memory_info().rss, "threads": process.num_threads(),
                        "status": process.status(),
                    })
            except (psutil.Error, OSError):
                continue
        if not samples:
            return None
        return {
            "process_tree": samples,
            "cpu_seconds": round(sum(sample["cpu_seconds"] for sample in samples), 3),
            "rss_bytes": sum(sample["rss_bytes"] for sample in samples),
            "threads": sum(sample["threads"] for sample in samples),
            "status": samples[0]["status"],
        }

    def record(self, elapsed, loop_started):
        # wall_delta_s is the time since the previous recorded sample (nominally ~5 s); large values mean the runner itself was starved.
        now = time.monotonic()
        wall_delta = now - self.last if self.last is not None else 0.0
        self.last = now
        entry = {"elapsed": round(elapsed, 2), "wall_delta_s": round(wall_delta, 3),
                 "procs": {name: self.read(name) for name in self.targets if self.targets[name].poll() is None}}
        self.sample_cost_ms = round((time.monotonic() - loop_started) * 1000, 1)
        entry["sample_cost_ms"] = self.sample_cost_ms
        self.ring.append(entry)

    def snapshot(self):
        """Call immediately at failure, before any sleep or teardown."""
        now = time.monotonic()
        report = {"unix": time.time(), "processes": {}, "recent_samples": list(self.ring)[-4:]}
        for name, child in self.targets.items():
            current = self.read(name) if child.poll() is None else None
            entry = {"pid": child.pid, "alive": current is not None, "exit_code": child.poll()}
            if current:
                entry.update(current)
                # CPU time is comparable only while the same processes were sampled.
                if len(self.ring) >= 2:
                    older, newer = self.ring[-2], self.ring[-1]
                    a, b = (older["procs"].get(name), newer["procs"].get(name))
                    if a and b and newer["wall_delta_s"] > 0:
                        before = {sample["pid"] for sample in a["process_tree"]}
                        after = {sample["pid"] for sample in b["process_tree"]}
                        if before == after:
                            entry["cpu_percent_last_interval"] = round((b["cpu_seconds"] - a["cpu_seconds"]) / newer["wall_delta_s"] * 100, 1)
            report["processes"][name] = entry
        try:
            memory = psutil.virtual_memory()
            report["system"] = {"cpu_count": psutil.cpu_count(), "per_cpu_percent_since_last_sample": psutil.cpu_percent(percpu=True),
                                "memory_available_bytes": memory.available, "memory_percent": memory.percent}
            disk = psutil.disk_io_counters()
            if disk:
                report["system"]["disk_busy_time_ms"] = getattr(disk, "busy_time", None)
                report["system"]["disk_read_write_bytes"] = [disk.read_bytes, disk.write_bytes]
        except (psutil.Error, OSError, AttributeError):
            pass
        report["runner_sample_intervals_s"] = [e["wall_delta_s"] for e in self.ring]
        report["runner_max_interval_s"] = max(report["runner_sample_intervals_s"], default=None)
        report["runner_sample_cost_ms"] = self.sample_cost_ms
        report["snapshot_cost_ms"] = round((time.monotonic() - now) * 1000, 1)
        return report


def failure_order(clients):
    """Clients that logged SOAK_FAILURE/exit, earliest first, by the unix= stamp in their own log; ones still running are listed last."""
    failed, running, unstamped = [], [], []
    for index, entry in clients.items():
        stamps = [float(part[5:]) for line in entry["last_events"] for part in line.split() if part.startswith("unix=")]
        if entry["exit_code"] is None:
            running.append(f"client-{index}")
        elif entry["exit_code"] != 0 and stamps:
            failed.append((min(stamps), f"client-{index}"))
        elif entry["exit_code"] != 0:
            unstamped.append(f"client-{index}")  # failed but its log has no unix= stamp
    first = min(failed)[0] if failed else None
    return {"failed": [{"client": name, "unix": stamp, "after_first_s": round(stamp - first, 3)} for stamp, name in sorted(failed)],
            "failed_without_timestamp": unstamped, "still_running": running}


def measure(output, host, clients, duration, telemetry=None):
    started = time.monotonic()
    server = psutil.Process(host.pid)
    latest_save = 0
    last_save_seen = started
    previous_sample = started
    with (output / "samples.csv").open("w", newline="", encoding="utf-8") as stream:
        table = csv.writer(stream)
        table.writerow(["elapsed_seconds", "server_rss_bytes", "server_cpu_seconds", "clients_running", "save_mtime_ns", "save_bytes"])
        while any(client.poll() is None for client, _ in clients):
            loop_started = time.monotonic()
            if host.poll() is not None or time.monotonic() - started > duration + 60:
                raise RuntimeError("server stopped or clients did not exit on time")
            for client, path in clients:
                if client.poll() not in (0, None):
                    raise RuntimeError(f"client failed, see {path}")
            processes = [server, *server.children(recursive=True)]
            rss = sum(process.memory_info().rss for process in processes)
            cpu = sum(times.user + times.system for times in (process.cpu_times() for process in processes))
            try:
                save = (output / "world.json").stat()
            except FileNotFoundError:
                # The save rotation can briefly move the prior main file.
                if time.monotonic() - last_save_seen > 35:
                    raise RuntimeError("primary save missing for more than 35 seconds")
                time.sleep(0.1)
                continue
            now = time.monotonic()
            if now - previous_sample > 30:
                raise RuntimeError("sampling paused for more than 30 seconds")
            previous_sample = now
            if save.st_mtime_ns != latest_save:
                latest_save = save.st_mtime_ns
                last_save_seen = now
            if now - last_save_seen > 35:
                raise RuntimeError("no new primary save for more than 35 seconds")
            table.writerow([round(now - started, 2), rss, round(cpu, 3), sum(client.poll() is None for client, _ in clients), latest_save, save.st_size])
            stream.flush()
            if telemetry:
                telemetry.record(now - started, loop_started)
            time.sleep(5)


def summarize(path):
    with path.open(newline="", encoding="utf-8") as stream:
        samples = list(csv.DictReader(stream))
    rss = [int(row["server_rss_bytes"]) for row in samples]
    steady_window = min(60, max(1, len(samples) // 4))
    save_versions = [int(row["save_mtime_ns"]) for row in samples]
    return {
        "samples": len(samples),
        "max_rss_bytes": max(rss),
        "early_median_rss_bytes": int(statistics.median(rss[steady_window:2 * steady_window])),
        "final_median_rss_bytes": int(statistics.median(rss[-steady_window:])),
        "cpu_seconds": float(samples[-1]["server_cpu_seconds"]),
        "observed_save_versions": len(set(save_versions)),
        "largest_observed_save_gap_seconds": max((b - a) / 1e9 for a, b in zip(save_versions, save_versions[1:])),
    }


if __name__ == "__main__":
    main()
