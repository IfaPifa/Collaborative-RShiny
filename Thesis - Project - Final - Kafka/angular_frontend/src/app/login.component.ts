import { ChangeDetectionStrategy, Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { AuthService } from './services/auth.service';

@Component({
  selector: 'app-login',
  standalone: true,
  imports: [CommonModule, FormsModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    <div class="min-h-screen bg-slate-50 flex flex-col justify-center items-center p-4 font-sans">
      
      <div class="mb-8 text-center">
        <h1 class="text-4xl font-bold text-primary-600 tracking-tight">ShinySwarm</h1>
        <p class="text-gray-500 mt-2">Collaborative R Shiny Environments</p>
      </div>

      <div class="w-full max-w-md bg-white rounded-xl shadow-lg border border-slate-200 p-8">
        <h2 class="text-2xl font-bold text-gray-800 mb-6 text-center">Sign In</h2>
        
        <form (ngSubmit)="handleLogin()">
          <div class="mb-5">
            <label class="block text-sm font-medium text-gray-700 mb-2">Username</label>
            <input 
              type="text" 
              [(ngModel)]="loginUsername" 
              name="username" 
              required
              class="form-input w-full px-4 py-2 border-gray-300 rounded-lg shadow-sm focus:ring-primary-500 focus:border-primary-500 transition"
              placeholder="Enter your username"
            >
          </div>
          
          <div class="mb-6">
            <label class="block text-sm font-medium text-gray-700 mb-2">Password</label>
            <input 
              type="password" 
              [(ngModel)]="loginPassword" 
              name="password" 
              required
              class="form-input w-full px-4 py-2 border-gray-300 rounded-lg shadow-sm focus:ring-primary-500 focus:border-primary-500 transition"
              placeholder="Enter your password"
            >
          </div>
          
          @if (loginError()) { 
            <div class="mb-5 p-3 bg-red-50 border border-red-200 rounded-lg text-center text-red-600 text-sm font-medium">
              {{ loginError() }}
            </div> 
          }
          
          <button 
            type="submit" 
            class="w-full bg-primary-600 text-white py-2.5 px-4 rounded-lg font-semibold shadow-md hover:bg-primary-700 focus:ring-2 focus:ring-offset-2 focus:ring-primary-500 transition disabled:opacity-70 flex justify-center items-center" 
            [disabled]="isLoading() || !loginUsername() || !loginPassword()"
          >
            @if (isLoading()) {
              <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
              </svg>
              Authenticating...
            } @else {
              Log In
            }
          </button>
        </form>
      </div>
      
      <div class="mt-8 text-sm text-gray-400">
        <p>System prototype for scientific collaboration.</p>
      </div>
    </div>
  `
})
export class LoginComponent {
  private authService = inject(AuthService);
  private router = inject(Router);

  // State Signals
  loginUsername = signal('');
  loginPassword = signal('');
  loginError = signal<string | null>(null);
  isLoading = signal(false);

  handleLogin() {
    // Basic validation
    if (!this.loginUsername() || !this.loginPassword()) {
      return;
    }

    this.isLoading.set(true);
    this.loginError.set(null); // Clear previous errors

    this.authService.login(this.loginUsername(), this.loginPassword()).subscribe({
      next: () => {
        this.isLoading.set(false);
        // Let the Angular Router take over and move them to the protected layout
        this.router.navigate(['/library']);
      },
      error: () => {
        this.isLoading.set(false);
        this.loginError.set('Invalid username or password. Please try again.');
      }
    });
  }
}