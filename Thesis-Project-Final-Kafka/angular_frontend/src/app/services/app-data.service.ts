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

  getSavedStates(appId?: number) {
    let url = `${this.API_URL}/states`;
    
    // If an appId is provided, append it to the URL so the backend can filter
    if (appId) {
      url += `?appId=${appId}`;
    }
    
    return this.http.get<SavedAppState[]>(url, { headers: this.getHeaders() });
  }

  // Note: stateData is a JSON string
  saveState(appId: number, name: string, stateData: string) {
    const payload = { appId, name, stateData };
    return this.http.post(
      `${this.API_URL}/states`, 
      payload, 
      { 
        headers: this.getHeaders(),
        responseType: 'text' // <-- ADD THIS LINE
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