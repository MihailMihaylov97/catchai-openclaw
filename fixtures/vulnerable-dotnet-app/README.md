# vulnerable-dotnet-app — contract test fixture

Deliberately vulnerable ASP.NET Core 6 project, used by
`tests/contract_test.sh` to verify catchai's openclaw-v1 envelope
contract for the .NET code path. **Do not run, deploy, or vendor
into a real project.**

The source files intentionally avoid "this is a test fixture" markers
(no XML doc disclaimer, no inline `// vulnerable:` comments) so that
L7 (semantic LLM review) treats them as production code. With those
markers present, L7 correctly suppresses findings as intentional —
production-correct, but breaks the contract test.

## Expected catchai detections

| Layer | Vulnerability | Where |
|---|---|---|
| L1 (deps) | Newtonsoft.Json 12.0.1 (multiple GHSA DoS), System.Text.Encodings.Web 4.7.0 (CVE-2021-26701), Microsoft.Data.SqlClient 2.0.0 (transitive advisories) | `VulnerableApp.csproj` |
| L2 (sast) | SQL injection via `SqlCommand.CommandText` string concat | `Controllers/UserController.cs:35` (`GetUser`) |
| L3 (secrets) | Hardcoded JWT secret + AWS access key | `Controllers/UserController.cs:20-21` |
| L4 (config) | `DetailedErrors: true` (top-level) leaks stack traces; plaintext DB password in `ConnectionStrings.Default` | `appsettings.json:5,3` |
| L5 (taint) | `[FromQuery] string name` → `_projectService.OpenProject(name)` → `Path.Combine("/srv/projects", name)` → `File.ReadAllBytes` | flow across `Controllers/UserController.cs:43` and `Services/ProjectService.cs:7` |
| L6 (authz) | `[HttpDelete]` without `[Authorize]` or `[AllowAnonymous]` decision | `Controllers/UserController.cs:48` (`DeleteUser`) |
| L7 (semantic) | Path traversal via `Path.Combine` absolute-path override (.NET's `Path.Combine` discards prior segments when a later segment starts with `/` or contains a rooted path — the .NET equivalent of Java's `new File(parent, child)` and Python's `os.path.join` quirk that L7 catches in those fixtures) | `Services/ProjectService.cs:7` |

The L7 finding is the load-bearing one — it's the unique-to-LLM
detection that no other layer catches. Pattern-matching SAST tools
look for `../` traversal sequences and miss `Path.Combine`'s
absolute-path-override behavior.

## Why no `// XXX security:` markers in the source

The Python and Java fixtures taught us that L7 correctly suppresses
findings on self-labeled test fixtures. To exercise the L7 code path,
the .NET source files must look like production code. The expected-
detection table above carries the metadata; the source carries no
hints.
