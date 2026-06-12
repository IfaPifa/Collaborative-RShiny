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
  savedBy: string;
}

@Injectable({ providedIn: 'root' })
export class AppDataService {
  private http = inject(HttpClient);
  private auth = inject(AuthService);
  private API_URL = '/api';

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

  getSavedStates(opts?: { appId?: number; sessionId?: string | null }) {
    const params: string[] = [];
    if (opts?.appId) params.push(`appId=${opts.appId}`);
    if (opts?.sessionId) params.push(`sessionId=${opts.sessionId}`);
    let url = `${this.API_URL}/states`;
    if (params.length) url += `?${params.join('&')}`;
    return this.http.get<SavedAppState[]>(url, { headers: this.getHeaders() });
  }

  // Note: stateData is a JSON string
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

  restoreState(stateId: number, sessionId?: string | null) {
    let url = `${this.API_URL}/states/${stateId}/restore`;
    if (sessionId) {
      url += `?sessionId=${sessionId}`;
    }
    return this.http.post(
      url, 
      {},
      { 
        headers: this.getHeaders(), 
        responseType: 'text' 
      }
    );
  }
}