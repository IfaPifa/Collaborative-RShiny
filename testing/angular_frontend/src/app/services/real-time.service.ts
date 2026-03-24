import { Injectable } from '@angular/core';
import { RxStomp } from '@stomp/rx-stomp';
import { map } from 'rxjs';

export interface PresenceMessage {
  username: string;
  type: 'JOIN' | 'LEAVE' | 'ROLE_UPDATE'; 
  sessionId: string;
}

@Injectable({ providedIn: 'root' })
export class RealTimeService {
  private rxStomp: RxStomp;

  constructor() {
    this.rxStomp = new RxStomp();
    this.rxStomp.configure({
      // 1. Connection URL
      // We use 'ws' (WebSocket) protocol. 
      // /ws-shiny is the endpoint we configured in Spring Boot.
      brokerURL: 'ws://localhost:8085/ws-shiny/websocket',
      
      // 2. Reconnect automatically if the server restarts
      reconnectDelay: 200, 
      
      // 3. Debug mode (logs to console so you can see if it connects)
      debug: (msg: string) => console.log(new Date(), msg),
    });

    this.rxStomp.activate();
  }

  // --- METHODS ---

  public joinSession(sessionId: string, username: string) {
    this.rxStomp.publish({
      destination: `/app/presence.join/${sessionId}`,
      body: JSON.stringify({ username, type: 'JOIN', sessionId })
    });
  }

  public leaveSession(sessionId: string, username: string) {
    this.rxStomp.publish({
      // Assuming your Spring Boot backend listens to .leave
      destination: `/app/presence.leave/${sessionId}`, 
      body: JSON.stringify({ username, type: 'LEAVE', sessionId })
    });
  }

  public getPresenceStream(sessionId: string) {
    // Listen to the specific topic for this session
    return this.rxStomp.watch(`/topic/presence/${sessionId}`).pipe(
      map(message => JSON.parse(message.body) as PresenceMessage)
    );
  }

  
}