package com.example.shinyswarm.Security;

import io.jsonwebtoken.Claims; // Import
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.userdetails.UserDetails; // Import
import org.springframework.stereotype.Service;

import java.security.Key;
import java.util.Date;
import java.util.function.Function; // Import

@Service
public class JwtService {

    @Value("${app.jwt.secret}")
    private String secretKey;

    private final long tokenValidity = 1000 * 60 * 60 * 24; 

    public String generateToken(String username) {
        // ... (Keep your existing generateToken code) ...
        Date now = new Date();
        Date expiryDate = new Date(now.getTime() + tokenValidity);

        return Jwts.builder()
                .setSubject(username)
                .setIssuedAt(now)
                .setExpiration(expiryDate)
                .signWith(getSignInKey())
                .compact();
    }

    // --- NEW METHODS FOR VALIDATION ---

    public String extractUsername(String token) {
        return extractClaim(token, Claims::getSubject);
    }

    public boolean isTokenValid(String token, UserDetails userDetails) {
        final String username = extractUsername(token);
        return (username.equals(userDetails.getUsername())) && !isTokenExpired(token);
    }

    private boolean isTokenExpired(String token) {
        return extractExpiration(token).before(new Date());
    }

    private Date extractExpiration(String token) {
        return extractClaim(token, Claims::getExpiration);
    }

    public <T> T extractClaim(String token, Function<Claims, T> claimsResolver) {
        final Claims claims = extractAllClaims(token);
        return claimsResolver.apply(claims);
    }

    private Claims extractAllClaims(String token) {
        return Jwts.parserBuilder()
                .setSigningKey(getSignInKey())
                .build()
                .parseClaimsJws(token)
                .getBody();
    }

    private Key getSignInKey() {
        byte[] keyBytes = Decoders.BASE64.decode(secretKey);
        return Keys.hmacShaKeyFor(keyBytes);
    }
}