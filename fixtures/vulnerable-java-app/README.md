# vulnerable-java-app — contract test fixture

Deliberately vulnerable Spring Boot project, used by `tests/contract_test.sh`
to verify catchai's openclaw-v1 envelope contract for the Java code path.
**Do not run, deploy, or vendor into a real project.**

The source files intentionally avoid "this is a test fixture" markers
(no docstring disclaimer, no inline `// vulnerable:` comments) so that
L7 (semantic LLM review) treats them as production code. With those
markers present, L7 correctly suppresses findings as intentional —
production-correct, but breaks the contract test.

## Expected catchai detections

| Layer | Vulnerability | Where |
|---|---|---|
| L1 (deps) | snakeyaml 1.30 (CVE-2022-1471), jackson-databind 2.9.0 (CVE-2017-7525 family) | `pom.xml` |
| L2 (sast) | SQL injection via JDBC string concat | `UserController.java:30` (`getUser`) |
| L3 (secrets) | Hardcoded JWT secret | `UserController.java:21` (`JWT_SECRET`) |
| L4 (config) | Actuator wildcard exposure (`management.endpoints.web.exposure.include: '*'`), plaintext datasource password | `application.yml:7,9` |
| L5 (taint) | `@RequestParam name` → `projectService.openProject(name)` → `new File("/srv/projects", name)` | flow across `UserController.java:38` and `ProjectService.java:11` |
| L6 (authz) | `@DeleteMapping` without `@PreAuthorize` or `@Secured` | `UserController.java:43` |
| L7 (semantic) | Path traversal via `new File(parent, child)` with absolute-path override (Java's `File(String, String)` constructor silently treats the second arg as absolute when it starts with `/` — the Java equivalent of `os.path.join`'s behavior that L7 catches in the Python fixture) | `ProjectService.java:11` |

The L7 finding is the load-bearing one — it's the unique-to-LLM
detection that no other layer catches. Pattern-matching SAST tools
look for `../` traversal sequences and miss the constructor's
absolute-path-override behavior.

## Why no `// XXX security:` markers in the source

The Python fixture taught us that L7 correctly suppresses findings
on self-labeled test fixtures. To exercise the L7 code path, the
Java source files must look like production code. The expected-
detection table above carries the metadata; the source carries no
hints.
