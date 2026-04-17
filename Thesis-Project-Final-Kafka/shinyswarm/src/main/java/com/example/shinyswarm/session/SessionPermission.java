// src/main/java/com/example/shinyswarm/session/SessionPermission.java
package com.example.shinyswarm.session;

public enum SessionPermission {
    VIEWER, // Read-only access
    EDITOR, // Can trigger computations in Shiny
    OWNER   // Can save state, invite others, delete session
}