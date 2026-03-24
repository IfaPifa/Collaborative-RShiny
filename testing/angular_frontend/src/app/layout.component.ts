import { ChangeDetectionStrategy, Component, inject, signal, OnInit, OnDestroy, computed } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink, RouterLinkActive, RouterOutlet, Router } from '@angular/router';
import { AuthService } from './services/auth.service';
import { CollabService, Notification } from './services/collab.service';

@Component({
  selector: 'app-layout',
  standalone: true,
  imports: [CommonModule, RouterOutlet, RouterLink, RouterLinkActive],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="flex flex-col h-screen bg-slate-50 font-sans relative">
      <nav class="bg-white shadow-sm w-full flex-shrink-0 z-20 border-b border-slate-200 relative">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between h-16">
            
            <div class="flex items-center">
              <span class="text-2xl font-bold text-primary-600">ShinySwarm</span>
              <div class="hidden sm:ml-6 sm:flex sm:space-x-8">
                <a routerLink="/library" routerLinkActive="active-nav" class="nav-link cursor-pointer">Library</a>
                <a routerLink="/saved-apps" routerLinkActive="active-nav" class="nav-link cursor-pointer">Saved Apps</a>
                <a routerLink="/collab-hub" routerLinkActive="active-nav" class="nav-link text-indigo-600 cursor-pointer">Collaboration</a>
              </div>
            </div>

            <div class="flex items-center gap-4">
              @if (authService.currentUser(); as user) {
                <div class="relative">
                  <button (click)="toggleNotifications()" class="p-2 text-gray-500 hover:text-indigo-600 transition relative">
                    <span class="text-xl">🔔</span>
                    @if (notifications().length > 0) {
                      <span class="absolute top-0 right-0 inline-flex items-center justify-center px-2 py-1 text-xs font-bold leading-none text-red-100 transform translate-x-1/4 -translate-y-1/4 bg-red-600 rounded-full">
                        {{ notifications().length }}
                      </span>
                    }
                  </button>

                  @if (showNotifications()) {
                    <div class="absolute right-0 mt-2 w-80 bg-white rounded-lg shadow-xl border border-gray-200 z-50 overflow-hidden">
                      <div class="px-4 py-2 bg-gray-50 border-b border-gray-200 font-medium text-gray-700 flex justify-between items-center">
                        <span>Inbox</span>
                        <button (click)="fetchNotifications()" class="text-xs text-blue-600 hover:underline">Refresh</button>
                      </div>
                      <div class="max-h-64 overflow-y-auto">
                        @for (note of notifications(); track note.id) {
                          <div (click)="handleNotificationClick(note)" class="p-4 border-b border-gray-100 hover:bg-indigo-50 cursor-pointer transition">
                            <p class="text-sm text-gray-800">{{ note.message }}</p>
                            <p class="text-xs text-gray-500 mt-1">{{ note.createdAt }}</p>
                            <span class="text-xs font-bold text-indigo-600 mt-2 block">Click to Join &rarr;</span>
                          </div>
                        } @empty {
                          <div class="p-6 text-center text-gray-500 text-sm">No new notifications.</div>
                        }
                      </div>
                    </div>
                  }
                </div>
                
                <span class="text-sm text-gray-600">User: {{ user.username }}</span>
                <button (click)="handleLogout()" class="bg-slate-100 text-slate-700 px-4 py-2 rounded-lg text-sm font-medium hover:bg-slate-200">Logout</button>
              }
            </div>
          </div>
        </div>
      </nav>

      <main class="flex-grow overflow-auto" (click)="showNotifications.set(false)">
        <router-outlet></router-outlet>
      </main>
    </div>
  `
})
export class LayoutComponent implements OnInit, OnDestroy {
  public authService = inject(AuthService);
  public collabService = inject(CollabService);
  private router = inject(Router);

  notifications = signal<Notification[]>([]);
  showNotifications = signal(false);
  private pollInterval: any;

  ngOnInit() {
    this.fetchNotifications();
    // Keep your polling logic isolated here
    this.pollInterval = setInterval(() => {
      if (this.authService.currentUser()) {
        this.fetchNotifications();
      }
    }, 5000); 
  }

  ngOnDestroy() {
    if (this.pollInterval) clearInterval(this.pollInterval);
  }

  fetchNotifications() {
    this.collabService.getNotifications().subscribe(notes => this.notifications.set(notes));
  }

  toggleNotifications() {
    this.showNotifications.update(v => !v);
  }

  handleNotificationClick(note: Notification) {
    this.collabService.dismissNotification(note.id).subscribe();
    this.notifications.update(list => list.filter(n => n.id !== note.id));
    this.showNotifications.set(false);

    // Navigate to the collaborative workspace via the router
    this.router.navigate(['/workspace', note.sessionId]);
  }

  handleLogout() {
    this.authService.logout();
    this.collabService.leaveSession();
    this.router.navigate(['/login']);
  }
}