import { ChangeDetectionStrategy, Component, computed, inject, signal, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';

import { AppDataService, ShinyApp } from './services/app-data.service';
import { CollabService } from './services/collab.service';

@Component({
  selector: 'app-library',
  standalone: true,
  imports: [CommonModule, FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="p-8 max-w-7xl mx-auto">
      
      <div class="flex flex-col sm:flex-row justify-between items-start sm:items-center mb-8 gap-4">
        <div>
          <h1 class="text-3xl font-bold text-gray-900">Application Library</h1>
          <p class="text-gray-500 mt-1">Browse and launch available R Shiny environments.</p>
        </div>
        
        <div class="relative w-full sm:w-72">
          <div class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
            <span class="text-gray-400">🔍</span>
          </div>
          <input 
            type="text" 
            [(ngModel)]="searchQuery" 
            placeholder="Search apps..." 
            class="form-input w-full pl-10 pr-4 py-2.5 border-gray-300 rounded-xl shadow-sm focus:ring-primary-500 focus:border-primary-500 transition"
          >
        </div>
      </div>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
        @for (app of filteredApps(); track app.id) {
          <div class="bg-white rounded-xl shadow-sm border border-slate-200 overflow-hidden flex flex-col hover:shadow-lg hover:-translate-y-1 transition-all duration-200">
            <div class="p-6 flex-grow">
              <div class="w-12 h-12 bg-primary-100 text-primary-600 rounded-lg flex items-center justify-center text-xl mb-4">
                📊
              </div>
              <h3 class="text-xl font-bold text-gray-800">{{ app.name }}</h3>
              <p class="text-gray-500 text-sm mt-2 line-clamp-3">{{ app.description }}</p>
            </div>
            <div class="p-4 bg-slate-50 border-t border-slate-100">
              <button 
                (click)="launchApp(app)" 
                class="w-full bg-primary-600 text-white py-2.5 px-4 rounded-lg font-semibold hover:bg-primary-700 transition shadow-sm flex items-center justify-center gap-2"
              >
                <span>Launch Solo</span> &rarr;
              </button>
            </div>
          </div>
        } @empty {
          <div class="col-span-full py-16 flex flex-col items-center justify-center bg-white rounded-xl border border-dashed border-gray-300">
            <span class="text-4xl text-gray-400 mb-3">📂</span>
            <p class="text-gray-500 font-medium text-lg">No applications found.</p>
            <p class="text-gray-400 text-sm mt-1">Try adjusting your search query.</p>
          </div>
        }
      </div>
    </div>
  `
})
export class LibraryComponent implements OnInit {
  private dataService = inject(AppDataService);
  private collabService = inject(CollabService);
  private router = inject(Router);

  // State
  shinyApps = signal<ShinyApp[]>([]);
  searchQuery = signal('');

  // Computed: Reactively filters apps based on the search query
  filteredApps = computed(() => {
    const q = this.searchQuery().toLowerCase();
    return this.shinyApps().filter(a => a.name.toLowerCase().includes(q));
  });

  ngOnInit() {
    // Fetch apps on load
    this.dataService.getApps().subscribe(apps => this.shinyApps.set(apps));
  }

  launchApp(app: ShinyApp) {
    // Ensure we aren't in a collab session if we launch solo
    this.collabService.leaveSession(); 
    
    // Set the selected app in our shared service
    this.dataService.selectedApp.set(app);
    
    // Navigate to the workspace (we can route to a generic "solo" workspace path)
    this.router.navigate(['/workspace', 'solo']);
  }
}