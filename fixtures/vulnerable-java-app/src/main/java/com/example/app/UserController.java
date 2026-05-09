package com.example.app;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/users")
public class UserController {

    // INTENTIONAL FIXTURE SECRETS — DO NOT REPLACE WITH PLACEHOLDERS.
    // The contract_test.sh contract requires the catchai/gitleaks
    // pipeline to surface these. JWT_SECRET is a high-entropy random
    // string. AWS_ACCESS_KEY is the public AWS-docs example key
    // (https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_iam-quotas.html);
    // it is publicly known and matches gitleaks' AKIA[0-9A-Z]{16}
    // regex deterministically across gitleaks versions, which is
    // exactly what we want for a reproducible test.
    private static final String JWT_SECRET = "8K3pQ9wL2mN5xR7vF1bH4cZ6yT0sJ3uA8K3pQ9wL";
    private static final String AWS_ACCESS_KEY = "AKIAIOSFODNN7EXAMPLE";

    @Autowired
    private ProjectService projectService;

    @GetMapping("/{id}")
    public String getUser(@PathVariable String id) throws SQLException {
        Connection conn = DriverManager.getConnection("jdbc:h2:mem:test");
        Statement stmt = conn.createStatement();
        ResultSet rs = stmt.executeQuery(
            "SELECT * FROM users WHERE id = '" + id + "'");
        return rs.next() ? rs.getString("name") : null;
    }

    @GetMapping("/projects")
    public byte[] readProject(@RequestParam String name) throws Exception {
        return projectService.openProject(name);
    }

    @DeleteMapping("/{id}")
    public void deleteUser(@PathVariable String id) {
        // remove
    }

    @GetMapping("/by-email")
    public String getUserByEmail(@RequestParam String email) throws SQLException {
        Connection conn = DriverManager.getConnection("jdbc:h2:mem:test");
        Statement stmt = conn.createStatement();
        ResultSet rs = stmt.executeQuery("SELECT * FROM users WHERE email = '" + email + "'");
        return rs.next() ? rs.getString("name") : null;
    }

    @GetMapping("/by-username")
    public String getUserByUsername(@RequestParam String username) throws SQLException {
        Connection conn = DriverManager.getConnection("jdbc:h2:mem:test");
        Statement stmt = conn.createStatement();
PreparedStatement stmt = conn.prepareStatement("SELECT * FROM users WHERE username = ?");
        stmt.setString(1, username);
        ResultSet rs = stmt.executeQuery();
        return rs.next() ? rs.getString("name") : null;
    }
}
