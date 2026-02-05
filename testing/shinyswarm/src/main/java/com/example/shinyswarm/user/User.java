package com.example.shinyswarm.user;

import jakarta.persistence.*;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.userdetails.UserDetails;
import java.util.Collection;
import java.util.List;

@Entity
// "user" is often a reserved SQL keyword, so "app_user" is safer
@Table(name = "app_user") 
public class User implements UserDetails {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(unique = true, nullable = false)
    private String username;

    @Column(nullable = false)
    private String password;
    
    // We can add email, etc. here later

    // --- Constructors ---
    public User() {}

    public User(String username, String password) {
        this.username = username;
        this.password = password;
    }

    // --- UserDetails Methods ---
    // These are required by Spring Security

    @Override
    public String getUsername() {
        return username;
    }
    
    @Override
    public String getPassword() {
        return password;
    }

    // For simplicity, we say all users are always "enabled"
    @Override
    public Collection<? extends GrantedAuthority> getAuthorities() {
        return List.of(); // No roles for now
    }
    
    @Override
    public boolean isAccountNonExpired() {
        return true;
    }

    @Override
    public boolean isAccountNonLocked() {
        return true;
    }

    @Override
    public boolean isCredentialsNonExpired() {
        return true;
    }

    @Override
    public boolean isEnabled() {
        return true;
    }
}