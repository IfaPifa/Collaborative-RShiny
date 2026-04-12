import { Injectable, signal, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { tap } from 'rxjs';

export interface User {
  id: number; // Changed from string to number to match Backend
  username: string;
}

interface LoginResponse {
  token: string;
  userId: number;
}

@Injectable({ providedIn: 'root' })
export class AuthService {
  private http = inject(HttpClient);
  // Ensure this matches your Spring Boot URL
  private API_URL = 'http://localhost:8085/api/auth';

  // State: Who is logged in?
  currentUser = signal<User | null>(null);

  // 1. Login Logic
  login(username: string, password: string) {
    return this.http.post<LoginResponse>(`${this.API_URL}/login`, { username, password })
      .pipe(
        tap(response => {
          // Save credentials to browser storage
          localStorage.setItem('authToken', response.token);
          localStorage.setItem('userId', response.userId.toString());
          localStorage.setItem('username', username);
          
          // Update State
          this.currentUser.set({ 
            id: response.userId, 
            username: username
          });
        })
      );
  }

  // 2. Logout Logic
  logout() {
    localStorage.removeItem('authToken');
    localStorage.removeItem('userId');
    localStorage.removeItem('username');
    this.currentUser.set(null);
  }

  // 3. Helper to get the token
  getToken() {
    return localStorage.getItem('authToken');
  }

  // 4. Restore Session (on page refresh)
  restoreSession(): boolean {
    const token = this.getToken();
    const uid = localStorage.getItem('userId');
    const uname = localStorage.getItem('username');

    if (token && uid && uname) {
      this.currentUser.set({ 
        id: parseInt(uid, 10), 
        username: uname 
      });
      return true;
    }
    return false;
  }
}