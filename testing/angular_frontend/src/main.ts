import { bootstrapApplication } from '@angular/platform-browser';
import { AppComponent } from './app/app.component';
import { provideHttpClient } from '@angular/common/http'; // Import this

bootstrapApplication(AppComponent, {
  providers: [
    provideHttpClient() // Add this
  ]
}).catch((err: any) => console.error(err)); // Note the (err: any) fix