import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { AuthService, User } from './auth.service';
import { ShinyApp } from './app-data.service';

// --- NEW TYPES ---
export type SessionPermission = 'OWNER' | 'EDITOR' | 'VIEWER';

export interface SessionParticipant {
  id: number;
  user: User; // The user object is now nested here
  permission: SessionPermission;
  online: boolean;
}

export interface CollaborationSession {
  id: string; 
  name: string;
  status: string;
  host: User;
  shinyApp: ShinyApp;
  // UPDATED: Now a list of participants, not just users
  participants: SessionParticipant[]; 
}

export interface Notification {
  id: number;
  message: string;
  sessionId: string;
  read: boolean;
  createdAt: string;
}

@Injectable({ providedIn: 'root' })
export class CollabService {
  private http = inject(HttpClient);
  private auth = inject(AuthService);
  private API_URL = 'http://localhost:8085/api/collab';

  // STATE
  activeSession = signal<CollaborationSession | null>(null);

  private getHeaders() {
    const token = this.auth.getToken();
    return new HttpHeaders({
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    });
  }

  // --- METHODS ---

  getMySessions() {
    return this.http.get<CollaborationSession[]>(this.API_URL, { headers: this.getHeaders() });
  }

  startSession(name: string, appId: number) {
    return this.http.post<CollaborationSession>(
      `${this.API_URL}/start`, 
      { name, appId }, 
      { headers: this.getHeaders() }
    );
  }

  joinSession(sessionId: string) {
    return this.http.post<CollaborationSession>(
      `${this.API_URL}/join`, 
      { sessionId }, 
      { headers: this.getHeaders() }
    );
  }


  inviteUser(sessionId: string, username: string, permission: SessionPermission) {
    return this.http.post(
      `${this.API_URL}/${sessionId}/invite`,
      { username, permission }, // Send permission in body
      { headers: this.getHeaders(), responseType: 'text' }
    );
  }

  saveSessionState(sessionId: string, name: string) {
    return this.http.post(
      `${this.API_URL}/${sessionId}/save`,
      { name },
      { headers: this.getHeaders(), responseType: 'text' }
    );
  }

  replaySession(sessionId: string) {
    return this.http.post(
        `${this.API_URL}/${sessionId}/replay`,
        {},
        { headers: this.getHeaders(), responseType: 'text' }
    );
  }

  restoreSession(sessionId: string, stateId: number) {
    return this.http.post(
        `${this.API_URL}/${sessionId}/restore/${stateId}`,
        {},
        { headers: this.getHeaders(), responseType: 'text' }
    );
  }
  
  leaveSession() {
    this.activeSession.set(null);
  }

  updatePermission(sessionId: string, username: string, permission: SessionPermission) {
    return this.http.put(
      `${this.API_URL}/${sessionId}/permissions`,
      { username, permission },
      { headers: this.getHeaders(), responseType: 'text' }
    );
  }

  getNotifications() {
    return this.http.get<Notification[]>(
      `${this.API_URL}/notifications`, 
      { headers: this.getHeaders() }
    );
  }

  dismissNotification(id: number) {
    return this.http.post(
      `${this.API_URL}/notifications/${id}/dismiss`,
      {},
      { headers: this.getHeaders(), responseType: 'text' }
    );
  }
}