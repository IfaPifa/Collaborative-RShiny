import { ChangeDetectionStrategy, Component, computed, inject, signal, SecurityContext } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { catchError, throwError } from 'rxjs'; 

// --- Interfaces for our data models ---
interface User {
  id: string;
  username: string;
  email: string;
}

interface ShinyApp {
  id: number;
  name: string;
  description: string;
  url: string;
}

interface SavedAppState {
  id: string;
  name: string;
  appId: number;
  appName: string;
  savedAt: Date;
  ownerId: string;
}

interface CollaborationSession {
  sessionId: string;
  appId: number;
  appName: string;
  ownerId: string;
  participants: {
    userId: string;
    username: string;
    permission: 'read' | 'write';
  }[];
}

// --- Mock Data (We still use this for app details and user lookups) ---
const MOCK_USERS: User[] = [
  { id: 'u1', username: 'alice', email: 'alice@example.com' },
  { id: 'u2', username: 'bob', email: 'bob@example.com' },
  { id: 'u3', username: 'charlie', email: 'charlie@example.com' },
];

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, FormsModule], // HttpClientModule is provided in main.ts
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="flex flex-col h-screen bg-slate-50 font-sans relative">
      
      @if (isLoading()) {
        <div class="absolute inset-0 bg-black/30 flex items-center justify-center z-50">
          <div class="w-16 h-16 border-4 border-t-primary-500 border-gray-200 rounded-full animate-spin"></div>
        </div>
      }

      @switch (currentPage()) {
        
        @case ('login') {
          <div class="flex-grow flex items-center justify-center p-4">
            <div class="w-full max-w-md bg-white rounded-lg shadow-md border border-slate-200 p-8">
              <h2 class="text-2xl font-bold text-center text-gray-800 mb-8">
                Shiny Portal Login
              </h2>
              <form (ngSubmit)="handleLogin()">
                <div class="mb-4">
                  <label for="username" class="block text-sm font-medium text-gray-700 mb-2">
                    Username
                  </label>
                  <input 
                    type="text" 
                    id="username" 
                    [(ngModel)]="loginUsername"
                    name="username"
                    class="form-input w-full border-gray-300 rounded-lg shadow-sm focus:ring-primary-500 focus:border-primary-500"
                    placeholder="Try 'alice' or 'bob'"
                  >
                </div>
                <div class="mb-6">
                  <label for="password" class="block text-sm font-medium text-gray-700 mb-2">
                    Password
                  </label>
                  <input 
                    type="password" 
                    id="password" 
                    [(ngModel)]="loginPassword"
                    name="password"
                    class="form-input w-full border-gray-300 rounded-lg shadow-sm focus:ring-primary-500 focus:border-primary-500"
                    placeholder="Try 'password'"
                  >
                </div>
                
                @if (loginError()) {
                  <div class="mb-4 text-center text-red-600 font-medium">
                    {{ loginError() }}
                  </div>
                }

                <button 
                  type="submit" 
                  class="w-full bg-primary-600 text-white py-2 px-4 rounded-lg font-semibold shadow-lg hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-opacity-50 transition duration-200"
                  [disabled]="isLoading()"
                >
                  @if(isLoading()) {
                    <div class="w-5 h-5 border-2 border-t-white border-gray-200 rounded-full animate-spin mx-auto"></div>
                  } @else {
                    Log In
                  }
                </button>
              </form>
            </div>
          </div>
        }

        @default {
          <nav class="bg-white shadow-sm w-full flex-shrink-0 z-10 border-b border-slate-200">
            <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
              <div class="flex justify-between h-16">
                <div class="flex items-center">
                  <span class="text-2xl font-bold text-primary-600">ShinySwarm</span>
                  <div class="hidden sm:ml-6 sm:flex sm:space-x-8">
                    <button (click)="goTo('library')" [class.active-nav]="currentPage() === 'library'" class="nav-link">
                      App Library
                    </button>
                    <button (click)="goTo('savedApps')" [class.active-nav]="currentPage() === 'savedApps'" class="nav-link">
                      Saved Apps
                    </button>
                    <button (click)="goTo('collabSessions')" [class.active-nav]="currentPage() === 'collabSessions'" class="nav-link">
                      Collaborative Sessions
                    </button>
                    <button (click)="goTo('profile')" [class.active-nav]="currentPage() === 'profile'" class="nav-link">
                      Profile
                    </button>
                  </div>
                </div>
                
                <div class="flex items-center">
                  @if (currentUser(); as user) {
                    <span class="text-sm text-gray-600 mr-4">
                      Welcome, <span class="font-medium">{{ user.username }}</span>
                    </span>
                    <button (click)="handleLogout()" class="bg-slate-100 text-slate-700 px-4 py-2 rounded-lg text-sm font-medium hover:bg-slate-200 transition duration-150">
                      Logout
                    </button>
                  }
                </div>
              </div>
            </div>
          </nav>

          <main class="flex-grow overflow-auto">
            @switch (currentPage()) {
              
              @case ('library') {
                <div class="p-8">
                  <div class="flex justify-between items-center mb-6">
                    <h1 class="text-2xl font-semibold text-gray-900">
                      Application Library
                    </h1>
                    <input 
                      type="text"
                      [(ngModel)]="appLibrarySearch"
                      placeholder="Search apps..."
                      class="form-input w-64 px-4 py-2 border-gray-300 rounded-lg shadow-sm focus:ring-primary-500 focus:border-primary-500"
                    >
                  </div>
                  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                    @for (app of filteredShinyApps(); track app.id) {
                      <div class="bg-white rounded-lg shadow-md border border-slate-200 overflow-hidden flex flex-col transition-all duration-300 hover:shadow-lg">
                        <div class="p-6 flex-grow">
                          <h3 class="text-lg font-semibold text-gray-800 mb-2">{{ app.name }}</h3>
                          <p class="text-gray-500 text-sm">{{ app.description }}</p>
                        </div>
                        <div class="p-4 bg-slate-50 border-t border-slate-100">
                          <button (click)="launchApp(app, null)" class="w-full bg-primary-600 text-white py-2 px-4 rounded-lg font-semibold shadow-lg hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-opacity-50 transition duration-200">
                            Launch App
                          </button>
                        </div>
                      </div>
                    } @empty {
                      <p class="text-gray-500 col-span-full text-center">No applications found.</p>
                    }
                  </div>
                </div>
              }

              @case ('savedApps') {
                <div class="p-8">
                  <div class="flex justify-between items-center mb-6">
                    <h1 class="text-2xl font-semibold text-gray-900">
                      Saved App States
                    </h1>
                    <input 
                      type="text"
                      [(ngModel)]="savedAppsSearch"
                      placeholder="Search saved states..."
                      class="form-input w-64 px-4 py-2 border-gray-300 rounded-lg shadow-sm focus:ring-primary-500 focus:border-primary-500"
                    >
                  </div>
                  @if (savedAppStates().length === 0) {
                    <div class="text-center text-gray-500 p-8 bg-white rounded-lg shadow-md border border-slate-200">
                      You have not saved any app states yet.
                    </div>
                  } @else {
                    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                      @for (save of filteredSavedApps(); track save.id) {
                        <div class="bg-white rounded-lg shadow-md border border-slate-200 overflow-hidden flex flex-col">
                          <div class="p-6 flex-grow">
                            <h3 class="text-lg font-semibold text-gray-800 mb-2">{{ save.name }}</h3>
                            <p class="text-gray-600 text-sm mb-1">App: {{ save.appName }}</p>
                            <p class="text-gray-400 text-xs">Saved: {{ save.savedAt | date:'medium' }}</p>
                          </div>
                          <div class="p-4 bg-slate-50 border-t border-slate-100 flex space-x-2">
                            <button (click)="loadSavedApp(save)" class="flex-grow bg-emerald-600 text-white py-2 px-4 rounded-lg font-semibold shadow-lg hover:bg-emerald-700 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-opacity-50 transition duration-200">
                              Load State
                            </button>
                            <button (click)="deleteSavedApp(save.id)" class="flex-shrink-0 bg-red-600 text-white py-2 px-4 rounded-lg font-semibold shadow-lg hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-red-500 focus:ring-opacity-50 transition duration-200" title="Delete this saved state">
                              Delete
                            </button>
                          </div>
                        </div>
                      } @empty {
                         <p class="text-gray-500 col-span-full text-center">No saved states match your search.</p>
                      }
                    </div>
                  }
                </div>
              }

              @case ('collabSessions') {
                <div class="p-8">
                  <div class="flex justify-between items-center mb-6">
                    <h1 class="text-2xl font-semibold text-gray-900">
                      Collaborative Sessions
                    </h1>
                    <input 
                      type="text"
                      [(ngModel)]="collabSearch"
                      placeholder="Search sessions..."
                      class="form-input w-64 px-4 py-2 border-gray-300 rounded-lg shadow-sm focus:ring-primary-500 focus:border-primary-500"
                    >
                  </div>
                  @if (activeCollaborations().length === 0) {
                    <div class="text-center text-gray-500 p-8 bg-white rounded-lg shadow-md border border-slate-200">
                      You are not part of any collaborative sessions.
                    </div>
                  } @else {
                    <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                      @for (session of filteredActiveCollaborations(); track session.sessionId) {
                        <div class="bg-white rounded-lg shadow-md border border-slate-200 overflow-hidden flex flex-col">
                          <div class="p-6 flex-grow">
                            <h3 class="text-lg font-semibold text-gray-800 mb-2">{{ session.appName }}</h3>
                            <p class="text-gray-600 text-sm mb-1">
                              Owner: <span class="font-medium">{{ getOwnerUsername(session) }}</span>
                            </p>
                            <p class="text-gray-600 text-sm mb-1">
                              Participants: <span class="font-medium">{{ session.participants.length }}</span>
                            </p>
                            <p class="text-gray-600 text-sm mb-1">
                              Your Permission:
                              <span class="font-medium" [class.text-primary-600]="myPermission(session) === 'read'" [class.text-amber-700]="myPermission(session) === 'write'">
                                {{ myPermission(session) === 'read' ? 'Read-Only' : 'Write' }}
                              </span>
                            </p>
                          </div>
                          <div class="p-4 bg-slate-50 border-t border-slate-100">
                            <button (click)="joinSession(session)" class="w-full bg-emerald-600 text-white py-2 px-4 rounded-lg font-semibold shadow-lg hover:bg-emerald-700 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:ring-opacity-50 transition duration-200">
                              Join Session
                            </button>
                          </div>
                        </div>
                      } @empty {
                         <p class="text-gray-500 col-span-full text-center">No sessions match your search.</p>
                      }
                    </div>
                  }
                </div>
              }

              @case ('profile') {
                <div class="p-8 max-w-2xl mx-auto">
                  <h1 class="text-2xl font-semibold text-gray-900 mb-6">User Profile</h1>
                  @if (currentUser(); as user) {
                    <div class="bg-white rounded-lg shadow-md border border-slate-200 p-6">
                      <div class="mb-4">
                        <label class="text-sm font-medium text-gray-500">Username</label>
                        <p class="text-lg text-gray-900">{{ user.username }}</p>
                      </div>
                      <div class="mb-4">
                        <label class="text-sm font-medium text-gray-500">Email</label>
                        <p class="text-lg text-gray-900">{{ user.email }}</p>
                      </div>
                    </div>
                  }
                </div>
              }

              @case ('shinyApp') {
                <div class="flex flex-col h-full">
                  <div class="p-4 bg-white border-b border-gray-200 flex-shrink-0 flex justify-between items-center">
                    <div class="flex items-center">
                      <button (click)="goTo('library')" class="bg-slate-100 text-slate-700 px-4 py-2 rounded-lg text-sm font-medium hover:bg-slate-200 transition duration-150">
                        &larr; Back to Library
                      </button>
                      @if (selectedApp(); as app) {
                        <span class="ml-4 text-lg font-semibold text-gray-700">Running: {{ app.name }}</span>
                      }
                    </div>
                    <div class="flex items-center space-x-2">
                      <button (click)="openSaveModal()" class="bg-primary-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-primary-700 transition duration-150">
                        Save State
                      </button>
                      <button (click)="openInviteModal()" class="bg-emerald-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-emerald-700 transition duration-150">
                        {{ currentSession() ? 'Manage Session' : 'Invite' }}
                      </button>
                    </div>
                  </div>
                  <div class="flex-grow overflow-hidden">
                    @if (safeAppUrl(); as url) {
                      <iframe [src]="url" class="w-full h-full border-none"></iframe>
                    } @else {
                      <div class="p-8 text-center text-gray-500">
                        No application selected or URL is invalid.
                      </div>
                    }
                  </div>
                </div>
              }
            }
          </main>
        }
      }
      
      @if (showSaveModal()) {
        <div class="absolute inset-0 bg-black/50 flex items-center justify-center z-40" (click)="closeSaveModal()">
          <div class="bg-white rounded-lg shadow-lg p-6 w-full max-w-sm" (click)="$event.stopPropagation()">
            <h3 class="text-xl font-semibold text-gray-800 mb-4">Save App State</h3>
            <div class="mb-4">
              <label for="saveName" class="block text-sm font-medium text-gray-700 mb-2">Save Name</label>
              <input type="text" id="saveName" [(ngModel)]="saveStateName" name="saveName" class="form-input w-full border-gray-300 rounded-lg shadow-sm focus:ring-primary-500 focus:border-primary-500" placeholder="e.g., 'Q4 Sales Analysis'">
            </div>
            <div class="flex justify-end space-x-2">
              <button (click)="closeSaveModal()" class="bg-white text-gray-700 px-4 py-2 rounded-lg text-sm font-medium border border-gray-300 hover:bg-gray-50 transition">
                Cancel
              </button>
              <button (click)="handleSaveState()" class="bg-primary-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-primary-700 transition">
                Save
              </button>
            </div>
          </div>
        </div>
      }

      @if (showInviteModal()) {
        <div class="absolute inset-0 bg-black/50 flex items-center justify-center z-40" (click)="closeInviteModal()">
          <div class="bg-white rounded-lg shadow-lg p-6 w-full max-w-lg" (click)="$event.stopPropagation()">
            <h3 class="text-xl font-semibold text-gray-800 mb-4">Manage Collaboration</h3>
            
            @if (currentPermission() === 'write') {
              <div class="mb-4 p-4 border rounded-lg bg-slate-50">
                <h4 class="text-lg font-semibold text-gray-700 mb-3">Invite User</h4>
                <div class="flex space-x-2 mb-2">
                  <input type="email" [(ngModel)]="inviteEmail" name="inviteEmail" class="form-input flex-grow px-4 py-2 border-gray-300 rounded-lg shadow-sm focus:ring-primary-500 focus:border-primary-500" placeholder="Try 'charlie@example.com'">
                  <select [(ngModel)]="invitePermission" name="invitePermission" class="form-select px-4 py-2 border-gray-300 rounded-lg shadow-sm focus:ring-primary-500 focus:border-primary-500">
                    <option value="read">Read-Only</option>
                    <option value="write">Write</option>
                  </select>
                </div>
                <button (click)="handleInviteUser()" class="w-full bg-emerald-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-emerald-700 transition">
                  Send Invite
                </button>
                @if (inviteError()) {
                  <p class="text-red-600 text-sm mt-2">{{ inviteError() }}</p>
                }
              </div>
            }

            <div class="max-h-64 overflow-y-auto">
              <h4 class="text-lg font-semibold text-gray-700 mb-2">Current Session</h4>
              @if (currentSession(); as session) {
                <ul class="space-y-2">
                  @for (p of session.participants; track p.userId) {
                    <li class="flex justify-between items-center p-3 bg-slate-50 border border-slate-200 rounded-lg">
                      <div class="flex-grow">
                        <span class="font-medium text-gray-800">{{ p.username }}</span>
                        @if (p.userId === session.ownerId) {
                          <span class="ml-2 px-2 py-0.5 rounded-full text-xs font-semibold bg-primary-100 text-primary-800">Owner</span>
                        }
                      </div>
                      
                      @if (isSessionOwner() && p.userId !== session.ownerId) {
                        <div class="flex items-center space-x-2">
                          <select 
                            [value]="p.permission"
                            (change)="updatePermission(p.userId, $event)"
                            class="form-select text-sm border-gray-300 rounded-md shadow-sm focus:ring-primary-500 focus:border-primary-500"
                          >
                            <option value="read">Read-Only</option>
                            <option value="write">Write</option>
                          </select>
                          <button 
                            (click)="removeParticipant(p.userId)"
                            class="text-red-600 hover:text-red-800 text-sm font-medium"
                          >
                            Remove
                          </button>
                        </div>
                      } @else {
                        <span 
                          class="px-3 py-1 rounded-full text-xs font-medium"
                          [class.bg-primary-100]="p.permission === 'read'"
                          [class.text-primary-800]="p.permission === 'read'"
                          [class.bg-amber-100]="p.permission === 'write'"
                          [class.text-amber-800]="p.permission === 'write'"
                        >
                          {{ p.permission === 'read' ? 'Read-Only' : (p.userId === session.ownerId ? 'Owner (Write)' : 'Write') }}
                        </span>
                      }
                    </li>
                  }
                </ul>
              } @else {
                <p class="text-gray-500 text-center p-4">You are the only one here.</p>
              }
            </div>

            <div class="flex justify-between items-center mt-6">
              @if (isSessionOwner()) {
                <button (click)="deleteSession()" class="bg-red-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-red-700 transition">
                  Delete Session
                </button>
              } @else {
                <button (click)="leaveSession()" class="bg-red-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-red-700 transition">
                  Leave Session
                </button>
              }
              <button (click)="closeInviteModal()" class="bg-white text-gray-700 px-4 py-2 rounded-lg text-sm font-medium border border-gray-300 hover:bg-gray-50 transition">
                Done
              </button>
            </div>
          </div>
        </div>
      }

    </div>
  `,
  styles: [
    `
      /* We moved the nav-link styles to styles.css
        but the :host style is perfect here.
      */
      :host {
        display: block;
        height: 100vh;
      }
    `
  ]
})
export class AppComponent {
  // --- Injected Services ---
  private sanitizer = inject(DomSanitizer);
  private http = inject(HttpClient); // <-- INJECTED HTTPCLIENT

  // --- API URL ---
  private API_URL = 'http://localhost:8085'; // <-- SPRING BOOT URL

  // --- State Signals ---
  currentUser = signal<User | null>(null);
  currentPage = signal<'login' | 'library' | 'profile' | 'shinyApp' | 'savedApps' | 'collabSessions'>('login');
  selectedApp = signal<ShinyApp | null>(null);
  isLoading = signal(false); 
  
  // Login form state
  loginUsername = signal('');
  loginPassword = signal('');
  loginError = signal<string | null>(null);

  // --- Data Signals ---
  shinyApps = signal<ShinyApp[]>([]);
  savedAppStates = signal<SavedAppState[]>([]); 
  allCollaborationSessions = signal<CollaborationSession[]>([]);

  // --- Search/Filter Signals ---
  appLibrarySearch = signal('');
  savedAppsSearch = signal('');
  collabSearch = signal('');

  // --- Computed Signals ---
  safeAppUrl = computed(() => {
    const app = this.selectedApp();
    if (app && app.url) {
      const sanitized = this.sanitizer.sanitize(SecurityContext.URL, app.url);
      if (sanitized) {
        return this.sanitizer.bypassSecurityTrustResourceUrl(sanitized);
      }
    }
    return null;
  });

  activeCollaborations = computed(() => {
    const user = this.currentUser();
    if (!user) return [];
    return this.allCollaborationSessions().filter(session => 
      session.participants.some(p => p.userId === user.id)
    );
  });

  filteredShinyApps = computed(() => {
    const search = this.appLibrarySearch().toLowerCase();
    if (!search) return this.shinyApps();
    return this.shinyApps().filter(app => 
      app.name.toLowerCase().includes(search) ||
      app.description.toLowerCase().includes(search)
    );
  });

  filteredSavedApps = computed(() => {
    const search = this.savedAppsSearch().toLowerCase();
    const states = this.savedAppStates();
    if (!search) return states;
    return states.filter(s => 
      s.name.toLowerCase().includes(search) ||
      s.appName.toLowerCase().includes(search)
    );
  });
  
  filteredActiveCollaborations = computed(() => {
    const search = this.collabSearch().toLowerCase();
    const sessions = this.activeCollaborations();
    if (!search) return sessions;
    return sessions.filter(s => 
      s.appName.toLowerCase().includes(search)
    );
  });

  isSessionOwner = computed(() => {
    const user = this.currentUser();
    const session = this.currentSession();
    if (!user || !session) return false;
    return user.id === session.ownerId;
  });

  currentPermission = computed(() => this.myPermission(this.currentSession()));

  // --- Modal and Session State ---
  showSaveModal = signal(false);
  saveStateName = signal('');
  
  showInviteModal = signal(false);
  inviteEmail = signal('');
  invitePermission = signal<'read' | 'write'>('read');
  inviteError = signal<string | null>(null);

  currentSession = signal<CollaborationSession | null>(null);

  // --- Component Methods ---

  simulateLoading(duration: number = 600): Promise<void> {
    this.isLoading.set(true);
    return new Promise(resolve => {
      setTimeout(() => {
        this.isLoading.set(false);
        resolve();
      }, duration);
    });
  }
  
  // ==========================================================
  // /// --- handleLogin METHOD --- ///
  // ==========================================================
  handleLogin(): void {
    this.isLoading.set(true);
    this.loginError.set(null); // Clear previous errors

    const username = this.loginUsername();
    const password = this.loginPassword();

    // Call the Spring Boot API
    this.http.post<{ token: string }>(`${this.API_URL}/api/auth/login`, { username, password })
      .pipe(
        catchError((err: HttpErrorResponse) => {
          // Handle login errors
          this.isLoading.set(false);
          if (err.status === 401) {
            this.loginError.set('Invalid username or password.');
          } else {
            this.loginError.set('A server error occurred. Please try again later.');
          }
          return throwError(() => err); // Re-throw the error
        })
      )
      .subscribe(response => {
        // --- Login Success ---
        // 1. Store the token in localStorage
        localStorage.setItem('authToken', response.token);

        // 2. Find the full user object from our MOCK_USERS list
        //    (This is a temporary bridge. In the future, we'd fetch
        //    this from a '/api/users/me' endpoint)
        const user = MOCK_USERS.find(u => u.username === username);

        // 3. Set the current user signal
        if (user) {
          this.currentUser.set(user);
        } else {
          // Fallback just in case mocks are out of sync
          this.currentUser.set({
            id: 'temp-id',
            username: username,
            email: 'temp-email'
          });
        }

        this.fetchApps();

        // 4. Navigate to the app library
        this.currentPage.set('library');
        this.loginUsername.set('');
        this.loginPassword.set('');
        this.isLoading.set(false);
      });
  }

  // ==========================================================
  // /// ---  handleLogout METHOD --- ///
  // ==========================================================
  handleLogout(): void {
    // Clear the token from storage
    localStorage.removeItem('authToken');

    // Reset all state
    this.currentUser.set(null);
    this.currentPage.set('login');
    this.selectedApp.set(null);
    this.currentSession.set(null); 
  }

  launchApp(app: ShinyApp, sessionToLoad: CollaborationSession | null): void {
    if (!this.currentUser()) {
      this.currentPage.set('login');
      return;
    }
    this.selectedApp.set(app);
    this.currentPage.set('shinyApp');
    this.currentSession.set(sessionToLoad); 
  }

  goTo(page: 'library' | 'profile' | 'savedApps' | 'collabSessions'): void {
    if (!this.currentUser()) {
      this.currentPage.set('login');
      return;
    }
    this.showInviteModal.set(false);
    this.showSaveModal.set(false);
    this.currentPage.set(page);
  }

  // ==========================================================
  // /// --- fetchApps METHOD --- ///
  // ==========================================================
  fetchApps(): void {
    // Note: In a real app, you should attach the Authorization header here.
    // Since we haven't set up an HttpInterceptor yet, we might need headers manually
    // or rely on the backend endpoint being public for now. 
    
    // Assuming the endpoint is protected, we add headers:
    const token = localStorage.getItem('authToken');
    const headers = { 'Authorization': `Bearer ${token}` };

    this.http.get<ShinyApp[]>(`${this.API_URL}/api/apps`, { headers })
      .pipe(
        catchError(err => {
          console.error('Failed to load apps', err);
          this.isLoading.set(false);
          return throwError(() => err);
        })
      )
      .subscribe(apps => {
        this.shinyApps.set(apps);
        this.isLoading.set(false);
      });
  }

  // --- Saved App Methods ---
  async loadSavedApp(savedState: SavedAppState): Promise<void> {
    await this.simulateLoading();
    const appToLoad = this.shinyApps().find(app => app.id === savedState.appId);
    if (appToLoad) {
      this.launchApp(appToLoad, null); 
      console.log('Loading app state:', savedState.name);
    }
  }

  async deleteSavedApp(saveId: string): Promise<void> {
    await this.simulateLoading();
    this.savedAppStates.update(states => 
      states.filter(state => state.id !== saveId)
    );
    console.log('Deleting app state:', saveId);
  }

  openSaveModal(): void {
    this.saveStateName.set('');
    this.showSaveModal.set(true);
  }

  closeSaveModal(): void {
    this.showSaveModal.set(false);
  }

  async handleSaveState(): Promise<void> {
    const app = this.selectedApp();
    const user = this.currentUser();
    const name = this.saveStateName();

    if (!app || !user || !name) return;

    await this.simulateLoading();
    const newState: SavedAppState = {
      // FIX: Replaced backtick with single quotes for compilation
      id: 'save_' + Math.random().toString(36).substring(2, 9),
      name: name,
      appId: app.id,
      appName: app.name,
      savedAt: new Date(),
      ownerId: user.id
    };

    this.savedAppStates.update(states => [newState, ...states]);
    console.log('Saving state:', newState);
    this.closeSaveModal();
  }

  // --- Collaboration Methods ---
  async joinSession(session: CollaborationSession): Promise<void> {
    await this.simulateLoading();
    const appToLoad = this.shinyApps().find(app => app.id === session.appId);
    if (appToLoad) {
      this.launchApp(appToLoad, session);
    } else {
      console.error('App for this session not found:', session.appId);
    }
  }

  myPermission(session: CollaborationSession | null): 'read' | 'write' | 'none' {
    const user = this.currentUser();
    if (!user || !session) return 'none';
    const participant = session.participants.find(p => p.userId === user.id);
    return participant ? participant.permission : 'none';
  }

  getOwnerUsername(session: CollaborationSession): string {
    const owner = session.participants.find(p => p.userId === session.ownerId);
    return owner ? owner.username : 'Unknown';
  }

  openInviteModal(): void {
    this.inviteEmail.set('');
    this.invitePermission.set('read');
    this.inviteError.set(null);
    this.showInviteModal.set(true);
  }

  closeInviteModal(): void {
    const session = this.currentSession();

    if (session) {
      // Save the session (add or update) to the global list
      this.allCollaborationSessions.update(allSessions => {
        const existingIndex = allSessions.findIndex(s => s.sessionId === session.sessionId);
        if (existingIndex > -1) {
          allSessions[existingIndex] = session;
          return [...allSessions];
        } else {
          return [...allSessions, session];
        }
      });
    }
    this.showInviteModal.set(false);
  }

  async handleInviteUser(): Promise<void> {
    const user = this.currentUser();
    const app = this.selectedApp();
    const email = this.inviteEmail();
    const permission = this.invitePermission();

    if (!user || !app) return;

    const userToInvite = MOCK_USERS.find(u => u.email === email);

    if (!userToInvite) {
      this.inviteError.set('User not found.');
      return;
    }
    if (userToInvite.id === user.id) {
      this.inviteError.set('You cannot invite yourself.');
      return;
    }

    await this.simulateLoading(400); // Quick load
    this.inviteError.set(null);
    this.inviteEmail.set('');

    const newParticipant = {
      userId: userToInvite.id,
      username: userToInvite.username,
      permission: permission
    };

    if (this.currentSession()) {
      this.currentSession.update(session => {
        if (!session) return null;
        const existing = session.participants.find(p => p.userId === newParticipant.userId);
        if (existing) {
          this.inviteError.set('User is already in this session.');
          return session; // Return original session if user exists
        }
        return {
          ...session,
          participants: [...session.participants, newParticipant]
        };
      });
    } else {
      const newSession: CollaborationSession = {
        // FIX: Replaced backtick with single quotes for compilation
        sessionId: 'sess_' + Math.random().toString(36).substring(2, 9),
        appId: app.id,
        appName: app.name,
        ownerId: user.id,
        participants: [
          { userId: user.id, username: user.username, permission: 'write' },
          newParticipant
        ]
      };
      this.currentSession.set(newSession);
      console.log('Starting new session:', newSession);
    }
  }

  // --- Collaboration Management Methods ---

  async updatePermission(userId: string, event: Event): Promise<void> {
    const permission = (event.target as HTMLSelectElement).value;
    await this.simulateLoading(300);
    this.currentSession.update(session => {
      if (!session) return null;
      return {
        ...session,
        participants: session.participants.map(p =>
          p.userId === userId ? { ...p, permission: permission as 'read' | 'write' } : p
        )
      };
    });
  }

  async removeParticipant(userId: string): Promise<void> {
    await this.simulateLoading();
    this.currentSession.update(session => {
      if (!session) return null;
      return {
        ...session,
        participants: session.participants.filter(p => p.userId !== userId)
      };
    });
  }

  async leaveSession(): Promise<void> {
    const user = this.currentUser();
    const session = this.currentSession();
    if (!user || !session) return;

    await this.simulateLoading();
    
    // Update the session in the global list by removing the user
    this.allCollaborationSessions.update(allSessions => {
      return allSessions.map(s => {
        if (s.sessionId === session.sessionId) {
          return {
            ...s,
            participants: s.participants.filter(p => p.userId !== user.id)
          };
        }
        return s;
      }).filter(s => s.participants.length > 0); // Optional: remove empty sessions
    });

    this.goTo('collabSessions'); // This also closes the modal
  }

  async deleteSession(): Promise<void> {
    const session = this.currentSession();
    if (!session || !this.isSessionOwner()) return;

    await this.simulateLoading();
    
    // Remove the session entirely from the global list
    this.allCollaborationSessions.update(allSessions => 
      allSessions.filter(s => s.sessionId !== session.sessionId)
    );
    
    this.goTo('collabSessions'); // This also closes the modal
  }
}