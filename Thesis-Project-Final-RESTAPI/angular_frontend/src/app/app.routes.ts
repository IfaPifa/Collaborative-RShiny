// app.routes.ts
import { Routes } from '@angular/router';
import { authGuard } from './auth.guard';

export const routes: Routes = [
  // The Login page is public, so it gets NO guard
  { 
    path: 'login', 
    loadComponent: () => import('./login.component').then(m => m.LoginComponent) 
  },
  
  // The Main Layout and all its children ARE protected by the authGuard
  { 
    path: '', 
    loadComponent: () => import('./layout.component').then(m => m.LayoutComponent),
    canActivate: [authGuard], // <--- Here is the magic line!
    children: [
      { path: 'library', loadComponent: () => import('./library.component').then(m => m.LibraryComponent) },
      { path: 'saved-apps', loadComponent: () => import('./saved-apps.component').then(m => m.SavedAppsComponent) },
      { path: 'collab-hub', loadComponent: () => import('./collab-hub.component').then(m => m.CollabHubComponent) },
      { path: 'workspace/:id', loadComponent: () => import('./workspace.component').then(m => m.WorkspaceComponent) },
      
      // Default fallback if they just go to "localhost:4200/"
      { path: '', redirectTo: 'library', pathMatch: 'full' } 
    ]
  },
  
  // Wildcard route: catch-all for bad URLs and send them to the protected area
  // (which will bounce them to login if they aren't authenticated)
  { path: '**', redirectTo: '' }
];