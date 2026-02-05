package com.example.shinyswarm.Security;

import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager; // <-- IMPORT
import org.springframework.security.authentication.BadCredentialsException; // <-- IMPORT
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken; // <-- IMPORT
import org.springframework.web.bind.annotation.*;

record LoginRequest(String username, String password) {}
record LoginResponse(String token) {}

@RestController
@RequestMapping("/api/auth")
public class AuthController {

    private final JwtService jwtService;
    private final AuthenticationManager authenticationManager; // <-- INJECT

    public AuthController(JwtService jwtService, AuthenticationManager authenticationManager) { // <-- UPDATE CONSTRUCTOR
        this.jwtService = jwtService;
        this.authenticationManager = authenticationManager;
    }

    @PostMapping("/login")
    public ResponseEntity<?> login(@RequestBody LoginRequest request) {
        
        try {
            // --- This is the new, secure logic ---
            // Spring Security will use our beans to check the username
            // and hashed password. It throws an exception if it fails.
            authenticationManager.authenticate(
                new UsernamePasswordAuthenticationToken(
                    request.username(),
                    request.password()
                )
            );
            // ----------------------------------------

            // If we get here, the user is valid.
            String token = jwtService.generateToken(request.username());
            return ResponseEntity.ok(new LoginResponse(token));

        } catch (BadCredentialsException e) {
            // If authentication fails, return "Unauthorized"
            return ResponseEntity.status(401).body("Invalid username or password.");
        }
    }
}