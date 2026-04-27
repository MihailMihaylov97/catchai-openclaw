package com.example.app;

import java.io.File;
import java.nio.file.Files;
import org.springframework.stereotype.Service;

@Service
public class ProjectService {

    public byte[] openProject(String project) throws Exception {
        File f = new File("/srv/projects", project);
        return Files.readAllBytes(f.toPath());
    }
}
