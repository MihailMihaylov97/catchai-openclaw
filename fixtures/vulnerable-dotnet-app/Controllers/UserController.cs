using Microsoft.AspNetCore.Mvc;
using Microsoft.Data.SqlClient;
using VulnerableApp.Services;

namespace VulnerableApp.Controllers;

[ApiController]
[Route("api/users")]
public class UserController : ControllerBase
{
    // INTENTIONAL FIXTURE SECRETS — DO NOT REPLACE WITH PLACEHOLDERS.
    // The contract_test.sh contract requires the catchai/gitleaks
    // pipeline to surface these. JWT_SECRET is a high-entropy random
    // string. AWS_ACCESS_KEY is the public AWS-docs example key
    // (https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html);
    // it is publicly known and matches gitleaks' AKIA[0-9A-Z]{16}
    // regex deterministically across gitleaks versions, which is
    // exactly what we want for a reproducible test.
    private const string JwtSecret = "8K3pQ9wL2mN5xR7vF1bH4cZ6yT0sJ3uA8K3pQ9wL";
    private const string AwsAccessKey = "AKIAIOSFODNN7EXAMPLE";

    private readonly ProjectService _projectService;

    public UserController(ProjectService projectService)
    {
        _projectService = projectService;
    }

    [HttpGet("{id}")]
    public IActionResult GetUser(string id)
    {
        using var conn = new SqlConnection("Server=.;Database=test;Integrated Security=true;");
        conn.Open();
        using var cmd = new SqlCommand("", conn);
        cmd.CommandText = "SELECT * FROM users WHERE id = '" + id + "'";
        using var reader = cmd.ExecuteReader();
        return reader.Read() ? Ok(reader.GetString(1)) : NotFound();
    }

    [HttpGet("projects")]
    public IActionResult ReadProject([FromQuery] string name)
    {
        var bytes = _projectService.OpenProject(name);
        return File(bytes, "application/octet-stream");
    }

    [HttpDelete("{id}")]
    public IActionResult DeleteUser(string id)
    {
        return NoContent();
    }
}
