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

    private static final String JWT_SECRET = "supersecret123456789012345678901234567890";

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
}
