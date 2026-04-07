import { Injectable, inject, signal } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { AuthService } from './auth.service';

export interface ShinyApp {
  id: number;
  name: string;
  description: string;
  url: string;
}

export interface SavedAppState {
  id: number;
  appName: string;
  name: string;
  stateData: string;
  createdAt: string;
}

@Injectable({ providedIn: 'root' })
export class AppDataService {
  private http = inject(HttpClient);
  private auth = inject(AuthService);
  private API_URL = 'http://localhost:8085/api';

  public selectedApp = signal<ShinyApp | null>(null);

  private getHeaders() {
    const token = this.auth.getToken();
    return new HttpHeaders({
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json'
    });
  }

  getApps() {
    return this.http.get<ShinyApp[]>(`${this.API_URL}/apps`, { headers: this.getHeaders() });
  }

  getSavedStates() {
    return this.http.get<SavedAppState[]>(`${this.API_URL}/states`, { headers: this.getHeaders() });
  }

  // Note: stateData is a JSON string
  // Trigger the backend to pull the latest state from Kafka and save it
  saveState(appId: number, name: string, sessionId?: string | null) {
    const payload = { appId, name, sessionId };
    return this.http.post(
      `${this.API_URL}/states`, 
      payload, 
      { 
        headers: this.getHeaders(),
        responseType: 'text' 
      } 
    );
  }

  // Trigger the backend to push the saved state into Kafka
  restoreStateToKafka(stateId: number) {
    return this.http.post(
      `${this.API_URL}/states/${stateId}/restore`, 
      {}, // Empty body
      { 
        headers: this.getHeaders(), 
        responseType: 'text' 
      }
    );
  }
}