import { ChangeDetectionStrategy, Component, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router } from '@angular/router';

import { AppDataService, SavedAppState, ShinyApp } from './services/app-data.service';
import { CollabService } from './services/collab.service';

@Component({
  selector: 'app-saved-apps',
  standalone: true,
  imports: [CommonModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="p-8 max-w-7xl mx-auto">
      
      <div class="mb-8">
        <h1 class="text-3xl font-bold text-gray-900">Saved Workspaces</h1>
        <p class="text-gray-500 mt-1">Pick up right where you left off from your previous solo sessions.</p>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        @for (save of savedAppStates(); track save.id) {
          <div class="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden flex flex-col hover:shadow-md transition">
            <div class="p-6 flex-grow">
              <div class="flex justify-between items-start mb-3">
                <span class="bg-emerald-100 text-emerald-800 text-xs px-2.5 py-1 rounded-full font-medium">Saved State</span>
                <span class="text-gray-400 text-xs flex items-center gap-1">🕒 {{ save.createdAt | date:'shortDate' }}</span>
              </div>
              <h3 class="text-xl font-bold text-gray-800 mb-1">{{ save.name }}</h3>
              <p class="text-gray-600 text-sm font-medium">App: <span class="text-indigo-600">{{ save.appName }}</span></p>
            </div>
            
            <div class="p-4 bg-slate-50 border-t border-slate-100">
              <button 
                (click)="loadSavedApp(save)" 
                class="w-full bg-emerald-600 text-white py-2 px-4 rounded-lg font-semibold hover:bg-emerald-700 transition shadow-sm flex justify-center items-center gap-2"
                [disabled]="isLoading()"
              >
                <span>Restore State</span>
              </button>
            </div>
          </div>
        } @empty {
          <div class="col-span-full py-16 flex flex-col items-center justify-center bg-white rounded-xl border border-dashed border-gray-300">
            <span class="text-4xl text-gray-400 mb-3">💾</span>
            <p class="text-gray-500 font-medium text-lg">No saved states found.</p>
            <p class="text-gray-400 text-sm mt-1">Save a snapshot inside a workspace to see it here.</p>
          </div>
        }
      </div>
    </div>
  `
})
export class SavedAppsComponent implements OnInit {
  private dataService = inject(AppDataService);
  private collabService = inject(CollabService);
  private router = inject(Router);

  savedAppStates = signal<SavedAppState[]>([]);
  shinyApps = signal<ShinyApp[]>([]);
  isLoading = signal(false);

  ngOnInit() {
    // We need both the saved states AND the original apps to cross-reference them
    this.dataService.getSavedStates().subscribe(states => this.savedAppStates.set(states));
    this.dataService.getApps().subscribe(apps => this.shinyApps.set(apps));
  }

  loadSavedApp(save: SavedAppState) {
    const app = this.shinyApps().find(a => a.name === save.appName);
    
    if (app) {
      this.isLoading.set(true);
      
      // 1. Leave any active session
      this.collabService.leaveSession();
      
      // 2. Set the selected app in the global state
      this.dataService.selectedApp.set(app);
      
      // 3. Navigate to the workspace
      this.router.navigate(['/workspace', 'solo']);

      // 4. Wait 3.5 seconds for the iframe and Kafka consumer to boot
      setTimeout(() => {
        this.dataService.restoreStateToKafka(save.id).subscribe({
          next: () => this.isLoading.set(false),
          error: () => {
            this.isLoading.set(false);
            alert('Failed to push state to Kafka.');
          }
        });
      }, 3500); // <-- INCREASED THIS TIMER
      
    } else {
      alert('The base application for this save no longer exists.');
    }
  }
}