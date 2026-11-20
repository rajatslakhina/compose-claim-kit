#!/usr/bin/env python3
"""Runs every case through `docker compose config --format json` (and `docker compose create` + `docker inspect`
for the `$$` cases) and writes the results to Tests/ComposeClaimKitTests/ParityFixture.swift, which ParityTests
compares with ComposeClaimKit's own reading. Needs Docker with the compose plugin. Each case runs in a new temp
directory with an empty environment (`env -i`) plus the case's shell variables."""
import json, os, subprocess, sys, tempfile

def case(name, compose, dotenv=None, shell=None):
    return {"name": name, "compose": compose, "dotenv": dotenv, "shell": shell or {}}

def svc(body):
    return "services:\n  s:\n    image: x\n" + body

PORTS = ["8080:80", "80", "127.0.0.1:5432:5432", "8000-8002:9000-9002", "53:53/udp", "9090-9091:8080",
         "[::1]:8081:81", "127.0.0.1::80", "3000-3001", "8000-8001:9000-9002", "80/xyz", "0:80", "70000:80",
         "1.2.3.4:5:6:7", "8080:80/SCTP"]
CASES = []
for index, port in enumerate(PORTS):
    CASES.append(case(f"port {port}", svc(f"    ports:\n      - \"{port}\"\n")))
CASES += [
    case("port unquoted", svc("    ports:\n      - 22:22\n      - 3000\n")),
    case("port flow", svc("    ports: [\"8080:80\", 443]\n")),
    case("port same indent", "services:\n  s:\n    image: x\n    ports:\n    - \"8080:80\"\n"),
    case("port long", svc("    ports:\n      - target: 80\n        published: \"8080\"\n        host_ip: 127.0.0.1\n"
                           "        protocol: udp\n      - target: 443\n")),
    case("port long range", svc("    ports:\n      - target: 80\n        published: 8000-8010\n")),
    case("expose", svc("    expose:\n      - \"3000\"\n      - 4000-4001\n")),
]
OPS = ["${V}", "$V", "${V:-d}", "${V-d}", "${V:+a}", "${V+a}", "${V:?boom}", "${V?boom}", "x${V}y", "$$V",
       "${V:-${W}}", "${V:-}", "${V:?}"]
for op in OPS:
    for state, shell in [("unset", {}), ("empty", {"V": ""}), ("set", {"V": "val"})]:
        CASES.append(case(f"{op} {state}", svc(f"    environment:\n      R: \"{op}\"\n"), shell=dict(shell, W="w")))
CASES += [
    case("dotenv vs shell", svc("    environment:\n      R: \"${V}\"\n"), dotenv="V=fromdotenv\n", shell={"V": "sh"}),
    case("dotenv only", svc("    environment:\n      R: \"${V}\"\n      S: \"${Q}\"\n"), dotenv="V=fromdotenv\n"),
    case("dotenv rules", svc("    environment:\n      A: \"${A}\"\n      B: \"${B}\"\n      C: \"${C}\"\n"
                             "      D: \"${D}\"\n      E: \"${E}\"\n      F: \"[${F}]\"\n      G: \"${G}\"\n"
                             "      H: \"${H}\"\n"),
         dotenv="# c\nA=plain value # trailing\nB=\"quoted # kept\"\nC='single'\nexport D=exported\nE=x#y\n"
                "F= spaced\nG=\"line\\nbreak\"\nH='lit\\n'\n"),
    case("dotenv not in container", svc("    environment:\n      R: \"${V}\"\n"), dotenv="V=1\nOTHER=2\n"),
    case("env list", svc("    environment:\n      - A=1\n      - B=\n      - C\n"), shell={"C": "fromshell"}),
    case("env list unset", svc("    environment:\n      - C\n")),
    case("env map null", svc("    environment:\n      C:\n      D: ~\n"), shell={"C": "x"}),
    case("env null from dotenv", svc("    environment:\n      - C\n"), dotenv="C=fromdotenv\n"),
    case("yaml quotes", svc("    environment:\n      A: 'it''s # here'\n      B: \"say \\\"hi\\\"\"\n      C: plain # c\n")),
    case("anchor", "x-common: &common\n  image: x\nservices:\n  s:\n    <<: *common\n"),
    case("env quoted keys", svc("    environment:\n      \"A\": '1'\n      'B': \"two # not a comment\"  # c\n")),
    case("undefined dependency", "services:\n  a:\n    image: x\n    depends_on: [nope]\n"),
    case("dependency map", "services:\n  a:\n    image: x\n    depends_on:\n      b:\n        condition: service_healthy\n"
                           "  b:\n    image: y\n"),
]

def run(case):
    with tempfile.TemporaryDirectory() as directory:
        with open(os.path.join(directory, "compose.yaml"), "w") as handle:
            handle.write(case["compose"])
        if case["dotenv"] is not None:
            with open(os.path.join(directory, ".env"), "w") as handle:
                handle.write(case["dotenv"])
        env = {"PATH": os.environ["PATH"], "HOME": os.environ["HOME"]}
        env.update(case["shell"])
        result = subprocess.run(["docker", "compose", "--project-name", "parity", "config", "--format", "json"],
                                cwd=directory, env=env, capture_output=True, text=True)
        if result.returncode != 0:
            return {"error": True}
        services = json.loads(result.stdout)["services"]
        out = {"error": False, "services": {}}
        for name, service in sorted(services.items()):
            ports = []
            for port in service.get("ports", []):
                ports.append([port.get("host_ip") or "", str(port.get("published") or ""), port["target"],
                              port.get("protocol", "tcp")])
            env_values = {}
            for key, value in (service.get("environment") or {}).items():
                # `config` writes a literal `$` as `$$` again; the container receives one `$`.
                env_values[key] = None if value is None else value.replace("$$", "$")
            out["services"][name] = {"ports": ports, "expose": [str(e) for e in service.get("expose", [])],
                                     "environment": env_values}
        return out

def swift_string(text):
    return json.dumps(text)

def main():
    lines = ["// Generated by Scripts/parity.py from `docker compose config --format json`. Do not edit by hand.",
             "// swiftlint:disable all", "", "struct ParityCase {", "    let name: String", "    let compose: String",
             "    let dotEnv: String?", "    let shell: [String: String]", "    let expected: String", "}", "",
             "let parityCases: [ParityCase] = ["]
    for item in CASES:
        result = run(item)
        print(item["name"], "->", json.dumps(result, sort_keys=True)[:110])
        shell = ", ".join(f"{swift_string(k)}: {swift_string(v)}" for k, v in sorted(item["shell"].items())) or ":"
        dotenv = "nil" if item["dotenv"] is None else swift_string(item["dotenv"])
        lines.append(f"    ParityCase(name: {swift_string(item['name'])}, compose: {swift_string(item['compose'])},")
        lines.append(f"               dotEnv: {dotenv}, shell: [{shell}],")
        lines.append(f"               expected: {swift_string(json.dumps(result, sort_keys=True))}),")
    lines.append("]")
    path = os.path.join(os.path.dirname(__file__), "..", "Tests", "ComposeClaimKitTests", "ParityFixture.swift")
    with open(path, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    print(f"{len(CASES)} cases written")

main()
