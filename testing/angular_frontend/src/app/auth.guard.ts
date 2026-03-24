import { inject } from '@angular/core';
import { CanActivateFn, Router } from '@angular/router';
import { AuthService } from './services/auth.service';

export const authGuard: CanActivateFn = (route, state) => {
  const authService = inject(AuthService);
  const router = inject(Router);

  // 1. Check if the user is already loaded in our Signal state
  if (authService.currentUser()) {
    return true;
  }

  // 2. If the Signal is null (e.g., they refreshed the page), try to restore from localStorage
  if (authService.restoreSession()) {
    return true; // Session restored successfully, allow access
  }

  // 3. If there is no valid session, redirect them safely to the login screen
  // Returning a parsed URL is the state-of-the-art Angular way to handle guard redirects
  return router.parseUrl('/login');
};