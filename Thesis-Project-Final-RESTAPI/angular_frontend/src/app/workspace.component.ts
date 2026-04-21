import { ChangeDetectionStrategy, Component, computed, inject, signal, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { DomSanitizer } from '@angular/platform-browser';
import { ActivatedRoute, Router } from '@angular/router';
import { Subscription } from 'rxjs';

import { AuthService } from './services/auth.service';
import { AppDataService, SavedAppState, ShinyApp } from './services/app-data.service';
import { CollabService, CollaborationSession, SessionPermission } from './services/collab.service';
import { RealTimeService, PresenceMessage } from './services/real-time.service';

import { ModalComponent } from './modal.component'; 



@Component({
  selector: 'app-workspace',
  standalone: true,
  imports: [CommonModule, FormsModule, ModalComponent], 
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="flex flex-col h-full bg-slate-50">
      <div class="p-4 bg-white border-b border-gray-200 flex justify-between items-center shadow-sm z-10">
        <div class="flex items-center gap-6">
          <button (click)="exitWorkspace()" class="text-slate-600 hover:text-slate-900 font-medium flex items-center gap-1 transition">
            <span class="text-xl">&larr;</span> Exit
          </button>
          
          <div class="flex items-center gap-4">
            @if (collabService.activeSession(); as session) {
              <div class="flex items-center -space-x-2 mr-2 border-r border-gray-100 pr-4">
                @for (user of activeUsers(); track user) {
                  <div class="relative group">
                    <div class="w-8 h-8 rounded-full border-2 border-white bg-indigo-500 text-white flex items-center justify-center text-xs font-bold shadow-sm cursor-default">
                      {{ user.charAt(0).toUpperCase() }}
                    </div>
                    <div class="absolute bottom-full left-1/2 -translate-x-1/2 mb-2 hidden group-hover:block bg-gray-800 text-white text-xs px-3 py-1 rounded shadow-lg z-50 whitespace-nowrap text-center">
                      <span class="font-bold">{{ user }}</span>
                      @if (getParticipantPermission(session, user); as perm) { 
                        <span class="block text-gray-300 text-[10px]">Role: {{ perm }}</span> 
                      }
                    </div>
                  </div>
                }
              </div>

              <div class="flex items-center gap-3">
                <span class="font-bold text-indigo-700 flex items-center gap-2">
                  <span class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span>
                  {{ session.name }}
                </span>
    
                <button (click)="handleCopySessionId(session.id)" 
                  class="text-xs bg-slate-100 hover:bg-slate-200 text-slate-600 px-2 py-1 rounded border border-slate-200 transition">
                  @if (copySuccess()) { <span>Copied!</span> } @else { <span>Copy ID</span> }
                </button>
                
                @if (isOwner()) {
                  <button (click)="showManageModal.set(true)" 
                    class="bg-slate-100 hover:bg-slate-200 text-slate-700 px-3 py-1.5 rounded-full text-xs font-medium border border-slate-200 shadow-sm transition">
                    ⚙️ Manage Roles
                  </button>
                }

                <button (click)="showInviteModal.set(true)" 
                  class="bg-indigo-600 text-white px-3 py-1.5 rounded-full text-xs font-medium hover:bg-indigo-700 shadow-sm transition">
                  + Invite
                </button>
              </div>
            } @else {
              <span class="font-bold text-gray-700">{{ dataService.selectedApp()?.name }} (Solo Mode)</span>
            }
          </div>
        </div>

        <div class="flex gap-2 items-center">
          @if (canEdit()) {
            <button (click)="showLoadModal.set(true)" class="bg-emerald-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-emerald-700 transition shadow-sm">
              Load Checkpoint
            </button>
            <button (click)="showSaveModal.set(true)" class="bg-primary-600 text-white px-4 py-2 rounded-lg text-sm font-medium hover:bg-primary-700 transition shadow-sm">
              Save State
            </button>
          } @else {
            <span class="text-xs text-gray-500 bg-gray-100 px-3 py-2 rounded border border-gray-200 flex items-center gap-1">
              🔒 View Only
            </span>
          }
        </div>
      </div>

      <div class="flex-grow relative bg-slate-200">
        @if (safeAppUrl(); as url) { 
          <iframe [src]="url" class="w-full h-full border-none shadow-inner"></iframe> 
        } @else {
          <div class="absolute inset-0 flex items-center justify-center text-gray-500">
            No application selected or URL invalid.
          </div>
        }
      </div>
    </div>

    <app-modal title="Manage Team Roles" [isOpen]="showManageModal()" (close)="showManageModal.set(false)">
      @if (collabService.activeSession(); as session) {
        <div class="flex-grow overflow-y-auto max-h-64 border border-gray-100 rounded-lg p-2 bg-gray-50 mb-4">
          @for (user of activeUsers(); track user) {
            <div class="flex justify-between items-center py-3 px-2 border-b border-gray-200 last:border-0">
              <span class="font-medium text-gray-800 flex items-center gap-2">
                <div class="w-6 h-6 rounded-full bg-indigo-200 text-indigo-700 flex items-center justify-center text-[10px] font-bold">
                  {{ user.charAt(0).toUpperCase() }}
                </div>
                {{ user }}
              </span>
              
              @if (user !== authService.currentUser()?.username) {
                <label class="flex items-center cursor-pointer hover:bg-indigo-50 px-2 py-1 rounded transition">
                  <input type="checkbox" class="form-checkbox h-4 w-4 text-indigo-600 border-gray-300 rounded cursor-pointer"
                         [checked]="getParticipantPermission(session, user) === 'EDITOR'"
                         (change)="togglePermission(user, $event)">
                  <span class="ml-2 text-sm text-gray-600 font-medium">Editor</span>
                </label>
              } @else {
                <span class="text-xs text-indigo-600 bg-indigo-100 px-2 py-1 rounded font-bold border border-indigo-200">OWNER</span>
              }
            </div>
          }
        </div>
      }
      <div class="flex justify-end pt-2">
        <button (click)="showManageModal.set(false)" class="bg-indigo-600 text-white px-6 py-2 rounded-lg font-medium hover:bg-indigo-700 transition">Done</button>
      </div>
    </app-modal>

    <app-modal title="Save State" [isOpen]="showSaveModal()" (close)="showSaveModal.set(false)">
      <input type="text" [(ngModel)]="saveStateName" placeholder="Name this save..." class="form-input w-full border-gray-300 rounded-lg shadow-sm mb-6 focus:ring-primary-500 focus:border-primary-500">
      <div class="flex justify-end gap-2">
        <button (click)="showSaveModal.set(false)" class="text-gray-500 hover:bg-gray-100 px-4 py-2 rounded-lg transition">Cancel</button>
        <button (click)="handleSaveState()" class="bg-primary-600 text-white px-4 py-2 rounded-lg hover:bg-primary-700 transition shadow-sm" [disabled]="!saveStateName()">Save</button>
      </div>
    </app-modal>

    <app-modal title="Load Checkpoint" [isOpen]="showLoadModal()" (close)="showLoadModal.set(false)">
      <div class="flex-grow overflow-y-auto max-h-[50vh] pr-2 mb-4">
        @for (save of savedAppStates(); track save.id) {
          <div class="border-b border-gray-100 py-3 last:border-0 hover:bg-gray-50 transition rounded px-2">
            <div class="flex justify-between items-center">
              <div>
                <p class="font-medium text-gray-800">{{ save.name }}</p>
                <p class="text-xs text-gray-500">{{ save.createdAt }}</p>
              </div>
              <button (click)="handleLoadFromModal(save)" class="bg-emerald-100 text-emerald-700 px-3 py-1 rounded text-sm font-medium hover:bg-emerald-200 transition">Load</button>
            </div>
          </div>
        } @empty { 
          <p class="text-gray-500 text-center py-6 bg-gray-50 rounded-lg border border-dashed border-gray-200">No saved states found.</p> 
        }
      </div>
      <div class="flex justify-end">
        <button (click)="showLoadModal.set(false)" class="text-gray-500 hover:bg-gray-100 px-4 py-2 rounded-lg transition">Cancel</button>
      </div>
    </app-modal>

    <app-modal title="Invite Collaborator" [isOpen]="showInviteModal()" (close)="showInviteModal.set(false)">
      <p class="text-sm text-gray-500 mb-4 -mt-2">They will receive an in-app notification and an email.</p>
      
      <label class="block text-sm font-medium text-gray-700 mb-1">Username</label>
      <input type="text" [(ngModel)]="inviteUsername" placeholder="e.g. bob" class="form-input w-full border-gray-300 rounded-lg shadow-sm mb-4 focus:ring-indigo-500 focus:border-indigo-500">

      <label class="block text-sm font-medium text-gray-700 mb-1">Permission</label>
      <select [(ngModel)]="invitePermission" class="form-select w-full border-gray-300 rounded-lg shadow-sm mb-6 focus:ring-indigo-500 focus:border-indigo-500">
        <option value="EDITOR">Editor (Can Interact & Save)</option>
        <option value="VIEWER">Viewer (Read Only)</option>
      </select>
      
      <div class="flex justify-end gap-2">
        <button (click)="showInviteModal.set(false)" class="text-gray-500 hover:bg-gray-100 px-4 py-2 rounded-lg transition">Cancel</button>
        <button (click)="handleSendInvite()" class="bg-indigo-600 text-white px-4 py-2 rounded-lg hover:bg-indigo-700 transition shadow-sm" [disabled]="!inviteUsername()">Send Invite</button>
      </div>
    </app-modal>
  `
})
export class WorkspaceComponent implements OnInit, OnDestroy {
  public authService = inject(AuthService);
  public collabService = inject(CollabService);
  // Changed dataService to public so the template can read it directly
  public dataService = inject(AppDataService); 
  private sanitizer = inject(DomSanitizer);
  private realTimeService = inject(RealTimeService);
  private router = inject(Router);
  private route = inject(ActivatedRoute);
  private currentSessionId: string | null = null;
  private currentUsername: string | null = null;

  // DELETED local selectedApp signal

  activeUsers = signal<string[]>([]);
  copySuccess = signal(false);
  savedAppStates = signal<SavedAppState[]>([]);
  
  // Modals
  showSaveModal = signal(false);
  showLoadModal = signal(false);
  showManageModal = signal(false);
  showInviteModal = signal(false);

  // Form Inputs
  saveStateName = signal('');
  inviteUsername = signal('');     
  invitePermission = signal<'EDITOR' | 'VIEWER'>('EDITOR');

  private presenceSub?: Subscription;

  isOwner = computed(() => {
    const session = this.collabService.activeSession();
    const user = this.authService.currentUser();
    return !!session && !!user && session.host.username === user.username;
  });

  canEdit = computed(() => {
    const session = this.collabService.activeSession();
    const user = this.authService.currentUser();
    const app = this.dataService.selectedApp();

    // 1. If there's no logged-in user, no editing allowed
    if (!user) return false;

    // 2. Scenario A: Collaborative Mode
    if (session) {
      const myParticipant = session.participants.find(p => p.user.username === user.username);
      return myParticipant ? (myParticipant.permission === 'OWNER' || myParticipant.permission === 'EDITOR') : false;
    }

    // 3. Scenario B: Solo Mode (If an app is selected and no session exists, you are the editor)
    if (app) {
      return true; 
    }

    return false;
  });

  safeAppUrl = computed(() => {
    // Read from dataService instead of local signal
    const app = this.dataService.selectedApp(); 
    const user = this.authService.currentUser();
    const session = this.collabService.activeSession(); 
    
    if (app && user) {
      const separator = app.url.includes('?') ? '&' : '?';
      let signedUrl = '';
      
      if (session) {
        const myPerm = this.getParticipantPermission(session, user.username) || 'VIEWER';
        // Use user.username instead of user.id
        signedUrl = `${app.url}${separator}sessionId=${session.id}&userId=${user.username}&permission=${myPerm}`; 
      } else {
        // Use user.username instead of user.id
        signedUrl = `${app.url}${separator}userId=${user.username}&permission=EDITOR`;
      }
      return this.sanitizer.bypassSecurityTrustResourceUrl(signedUrl);
    }
    return null;
  });

  ngOnInit() {
    this.dataService.getSavedStates().subscribe(states => this.savedAppStates.set(states));

    const user = this.authService.currentUser();
    // Read the ID from the URL (e.g., /workspace/1234-abcd)
    const sessionId = this.route.snapshot.paramMap.get('id');

    if (!user) return; // The auth guard handles kicking unauthenticated users out

    if (sessionId && sessionId !== 'solo') {
      // --- COLLABORATIVE MODE ---
      const currentSession = this.collabService.activeSession();

      if (currentSession && currentSession.id === sessionId) {
        // Scenario A: We arrived from the Hub, session is already in memory
        this.setupWorkspace(currentSession, user);
      } else {
        // Scenario B: We refreshed the page or clicked a notification. Fetch from backend!
        this.collabService.joinSession(sessionId).subscribe({
          next: (session) => {
            this.collabService.activeSession.set(session);
            this.setupWorkspace(session, user);
          },
          error: () => {
            alert("Session not found or access denied.");
            this.router.navigate(['/library']);
          }
        });
      }
    } else {
      // --- SOLO MODE ---
      if (!this.dataService.selectedApp()) { 
        this.router.navigate(['/library']);
      }
    }
  }

  // Helper method to keep your ngOnInit clean
  private setupWorkspace(session: CollaborationSession, user: any) {
    this.currentSessionId = session.id; 
    this.currentUsername = user.username; 
    this.dataService.selectedApp.set(session.shinyApp); 
      
    const onlineParticipants = session.participants.filter(p => p.online);
    const uniqueUsers = new Set(onlineParticipants.map(p => p.user.username));
    uniqueUsers.add(user.username);
    
    this.activeUsers.set(Array.from(uniqueUsers));

    this.realTimeService.joinSession(session.id, user.username);
    this.presenceSub = this.realTimeService.getPresenceStream(session.id).subscribe(msg => {
      this.handlePresenceUpdate(msg);
    });

    // --- ADD THIS NEW BLOCK ---
    // Give the Shiny iframe and R Kafka Consumer 3.5 seconds to fully boot 
    // before we ask the backend to blast the last known state into the queue.
    setTimeout(() => {
      this.collabService.replaySession(session.id).subscribe({
        next: () => console.log('🔄 Replayed previous session state!'),
        error: (err) => console.warn('No previous state found to replay.')
      });
    }, 3500); 
  }

  ngOnDestroy() {
    console.log(`[FRONTEND-SENDER] 🗑️ ngOnDestroy() fired.`);
    if (this.presenceSub) {
      this.presenceSub.unsubscribe();
    }

    if (this.currentSessionId && this.currentUsername) {
      console.log(`[FRONTEND-SENDER] 📤 Safety net triggered. Sending LEAVE for ${this.currentUsername}`);
      this.realTimeService.leaveSession(this.currentSessionId, this.currentUsername);
    }

    this.collabService.leaveSession();
    this.dataService.selectedApp.set(null); 
  }

  getParticipantPermission(session: CollaborationSession, username: string): string | undefined {
    return session.participants.find(p => p.user.username === username)?.permission;
  }

  exitWorkspace() {
    console.log(`[FRONTEND-SENDER] 📤 exitWorkspace() clicked. Sending LEAVE for ${this.currentUsername}`);
    
    if (this.currentSessionId && this.currentUsername) {
      this.realTimeService.leaveSession(this.currentSessionId, this.currentUsername);
    }

    this.currentSessionId = null;
    this.currentUsername = null;
    this.collabService.leaveSession();
    this.dataService.selectedApp.set(null); 
    this.router.navigate(['/library']);
  }

  handleCopySessionId(id: string) {
    navigator.clipboard.writeText(id).then(() => {
      this.copySuccess.set(true);
      setTimeout(() => this.copySuccess.set(false), 2000); 
    });
  }

  handlePresenceUpdate(msg: PresenceMessage) {
    console.log(`[FRONTEND-RECEIVER] 📥 Received presence update from WebSocket:`, msg);

    if (msg.type === 'ROLE_UPDATE') {
      this.collabService.joinSession(msg.sessionId).subscribe(session => {
        this.collabService.activeSession.set(session);
        // Relay the new permission into the Shiny iframe via postMessage
        const user = this.authService.currentUser();
        if (user) {
          const myPerm = this.getParticipantPermission(session, user.username) || 'VIEWER';
          const iframe = document.querySelector('iframe') as HTMLIFrameElement;
          if (iframe?.contentWindow) {
            iframe.contentWindow.postMessage({ type: 'ROLE_UPDATE', permission: myPerm }, '*');
          }
        }
      });
      return; 
    }

    this.activeUsers.update(users => {
      if (msg.type === 'JOIN') return users.includes(msg.username) ? users : [...users, msg.username];
      if (msg.type === 'LEAVE') return users.filter(u => u !== msg.username);
      return users;
    });
  }

  togglePermission(username: string, event: Event) {
    const isChecked = (event.target as HTMLInputElement).checked;
    const newRole: SessionPermission = isChecked ? 'EDITOR' : 'VIEWER';
    const session = this.collabService.activeSession();
    
    if (!session) return;
    
    this.collabService.updatePermission(session.id, username, newRole).subscribe({
      next: () => console.log(`Changed ${username} to ${newRole}`),
      error: () => alert("Failed to change permission")
    });
  }

  handleSendInvite() {
    const session = this.collabService.activeSession();
    if (!session || !this.inviteUsername()) return;

    this.collabService.inviteUser(session.id, this.inviteUsername(), this.invitePermission()).subscribe({
      next: () => {
        this.showInviteModal.set(false);
        this.inviteUsername.set('');
        alert("Invite sent!");
      },
      error: (err) => alert("Failed to send invite: " + (err.error || "User not found"))
    });
  }

  handleSaveState() {
    const app = this.dataService.selectedApp(); 
    const name = this.saveStateName();
    const currentSession = this.collabService.activeSession();

    if (!app || !name) return;

    if (currentSession) {
      // Collaborative Save (Uses the CollabService)
      this.collabService.saveSessionState(currentSession.id, name).subscribe({
        next: () => {
          this.showSaveModal.set(false);
          this.saveStateName.set('');
          alert('Team Snapshot Saved securely from Kafka!');
        },
        error: (err) => alert('Error saving session: ' + (err.error || 'Unknown error'))
      });
    } else {
      // Solo Save (Backend will look up the Kafka state using the Username)
      this.dataService.saveState(app.id, name, null).subscribe({
        next: () => {
          this.showSaveModal.set(false);
          this.saveStateName.set('');
          alert('Solo State Saved securely from Kafka!');
        },
        error: (err) => alert('Error saving state: ' + (err.error || 'Unknown error'))
      });
    }
  }

  handleLoadFromModal(save: SavedAppState) {
    this.showLoadModal.set(false);
    const currentSession = this.collabService.activeSession();

    if (currentSession) {
      this.collabService.restoreSession(currentSession.id, save.id).subscribe({
        next: () => alert('State restored for the group!'),
        error: () => alert('Failed to restore state')
      });
    } else {
      this.dataService.restoreStateToKafka(save.id).subscribe({
        next: () => alert('State loaded!'),
        error: () => alert('Failed to load state')
      });
    }
  }
}