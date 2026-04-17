import { ChangeDetectionStrategy, Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { CollabService, CollaborationSession } from './services/collab.service';
import { AppDataService, ShinyApp } from './services/app-data.service';
import { ModalComponent } from './modal.component';

@Component({
  selector: 'app-collab-hub',
  standalone: true,
  imports: [CommonModule, FormsModule, ModalComponent],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="p-8 max-w-7xl mx-auto">
      
      <div class="flex justify-between items-center mb-8">
        <div>
          <h1 class="text-3xl font-bold text-indigo-900">Collaboration Hub</h1>
          <p class="text-gray-500 mt-2">Manage your active team sessions and join new ones.</p>
        </div>
        <button (click)="showCreateSessionModal.set(true)" class="bg-indigo-600 text-white px-5 py-2.5 rounded-lg font-medium hover:bg-indigo-700 shadow-sm transition flex items-center gap-2">
          <span>+</span> New Session
        </button>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        @for (session of mySessions(); track session.id) {
          <div class="bg-white rounded-xl shadow-sm border border-gray-200 border-l-4 border-l-indigo-500 p-6 flex flex-col hover:shadow-md transition">
            <div class="flex justify-between items-start mb-4">
              <div>
                <h3 class="text-xl font-bold text-gray-800">{{ session.name }}</h3>
                <p class="text-sm text-gray-500 mt-1">App: <span class="font-medium">{{ session.shinyApp.name }}</span></p>
                <p class="text-sm text-gray-500">Host: {{ session.host.username }}</p>
              </div>
              <span class="bg-green-100 text-green-800 text-xs px-2.5 py-1 rounded-full font-medium">{{ session.status }}</span>
            </div>
            
            <div class="mt-auto pt-4 border-t border-gray-100">
              <div class="flex justify-between items-center mb-4">
                <span class="text-sm text-gray-600 flex items-center gap-1">
                  👥 {{ session.participants.length }} participants
                </span>
              </div>
              <button (click)="enterSession(session)" class="w-full bg-indigo-50 text-indigo-700 py-2 rounded-lg font-semibold hover:bg-indigo-100 transition">
                Enter Workspace &rarr;
              </button>
            </div>
          </div>
        } @empty {
          <div class="col-span-full flex flex-col items-center justify-center py-16 bg-white rounded-xl border border-dashed border-gray-300">
            <span class="text-4xl mb-4">🚀</span>
            <h3 class="text-lg font-medium text-gray-900">No active sessions</h3>
            <p class="text-gray-500 text-center max-w-sm mt-1">You aren't part of any active collaborative sessions. Create one or join via an invite code.</p>
          </div>
        }
      </div>

      <div class="mt-12 p-8 bg-white border border-gray-200 shadow-sm rounded-xl max-w-2xl mx-auto text-center">
        <h3 class="text-xl font-bold text-gray-800 mb-2">Have an Invite Code?</h3>
        <p class="text-gray-500 mb-6">Paste the session UUID provided by your colleague to join their workspace.</p>
        <div class="flex flex-col sm:flex-row gap-3 justify-center">
          <input type="text" [(ngModel)]="joinSessionId" placeholder="Paste Session UUID here..." class="form-input w-full sm:w-96 border-gray-300 rounded-lg focus:ring-indigo-500 focus:border-indigo-500">
          <button (click)="handleJoinSession()" [disabled]="!joinSessionId() || isLoading()" class="bg-slate-800 text-white px-8 py-2.5 rounded-lg font-medium hover:bg-slate-900 transition disabled:opacity-50">
            Join Room
          </button>
        </div>
      </div>
    </div>

    <app-modal 
      title="Start Collaboration" 
      [isOpen]="showCreateSessionModal()" 
      (close)="showCreateSessionModal.set(false)"
    >
      <div class="space-y-4">
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Session Name</label>
          <input type="text" [(ngModel)]="newSessionName" placeholder="e.g. Q1 Budget Review" class="form-input w-full border-gray-300 rounded-lg focus:ring-indigo-500 focus:border-indigo-500">
        </div>
        
        <div>
          <label class="block text-sm font-medium text-gray-700 mb-1">Select Shiny App</label>
          <select [(ngModel)]="newSessionAppId" class="form-select w-full border-gray-300 rounded-lg focus:ring-indigo-500 focus:border-indigo-500">
            <option [ngValue]="null" disabled selected>Choose an application...</option>
            @for (app of shinyApps(); track app.id) {
              <option [value]="app.id">{{ app.name }}</option>
            }
          </select>
        </div>

        <div class="flex justify-end gap-3 mt-6 pt-4 border-t border-gray-100">
          <button (click)="showCreateSessionModal.set(false)" class="text-gray-600 hover:bg-gray-100 px-4 py-2 rounded-lg transition font-medium">Cancel</button>
          <button (click)="handleCreateSession()" [disabled]="!newSessionName() || !newSessionAppId() || isLoading()" class="bg-indigo-600 text-white px-5 py-2 rounded-lg font-medium hover:bg-indigo-700 transition disabled:opacity-50">
            Create & Enter
          </button>
        </div>
      </div>
    </app-modal>
  `
})
export class CollabHubComponent implements OnInit {
  public collabService = inject(CollabService);
  private dataService = inject(AppDataService);
  private router = inject(Router);

  // State
  mySessions = signal<CollaborationSession[]>([]);
  shinyApps = signal<ShinyApp[]>([]);
  isLoading = signal(false);

  // Modal State
  showCreateSessionModal = signal(false);
  newSessionName = signal('');
  newSessionAppId = signal<number | null>(null);
  joinSessionId = signal('');

  ngOnInit() {
    this.refreshData();
  }

  refreshData() {
    this.collabService.getMySessions().subscribe(sessions => this.mySessions.set(sessions));
    // We need apps to populate the "Create Session" dropdown
    this.dataService.getApps().subscribe(apps => this.shinyApps.set(apps));
  }

  enterSession(session: CollaborationSession) {
    // 1. Save the session to the global state FIRST
    this.collabService.activeSession.set(session);
    
    // 2. THEN navigate to the workspace
    this.router.navigate(['/workspace', session.id]);
  }

  handleCreateSession() {
    if (!this.newSessionName() || !this.newSessionAppId()) return;
    this.isLoading.set(true);
    
    this.collabService.startSession(this.newSessionName(), this.newSessionAppId()!).subscribe({
      next: (session) => {
        this.isLoading.set(false);
        this.showCreateSessionModal.set(false);
        // Reset form
        this.newSessionName.set('');
        this.newSessionAppId.set(null);
        this.enterSession(session);
      },
      error: () => {
        this.isLoading.set(false);
        alert("Failed to start session");
      }
    });
  }

  handleJoinSession() {
    if (!this.joinSessionId()) return;
    this.isLoading.set(true);
    
    this.collabService.joinSession(this.joinSessionId()).subscribe({
      next: (session) => {
        this.isLoading.set(false);
        this.joinSessionId.set('');
        this.enterSession(session);
      },
      error: () => {
        this.isLoading.set(false);
        alert("Invalid Session ID or Session Closed");
      }
    });
  }
}