namespace VulnerableApp.Services;

public class ProjectService
{
    public byte[] OpenProject(string project)
    {
        var path = Path.Combine("/srv/projects", project);
        return File.ReadAllBytes(path);
    }
}
