import { ChangeDetectionStrategy, Component, EventEmitter, Input, Output } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-modal',
  standalone: true,
  imports: [CommonModule],
  changeDetection: ChangeDetectionStrategy.OnPush,
  template: `
    @if (isOpen) {
      <div 
        class="fixed inset-0 bg-black/50 flex items-center justify-center z-50 backdrop-blur-sm transition-opacity" 
        (click)="close.emit()"
      >
        <div 
          class="bg-white rounded-xl shadow-2xl p-6 w-full max-w-md transform transition-all" 
          (click)="$event.stopPropagation()"
        >
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-xl font-bold text-gray-900">{{ title }}</h3>
            <button (click)="close.emit()" class="text-gray-400 hover:text-gray-600 transition">
              <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
              </svg>
            </button>
          </div>
          
          <div class="mt-2">
            <ng-content></ng-content>
          </div>
        </div>
      </div>
    }
  `
})
export class ModalComponent {
  @Input({ required: true }) title!: string;
  @Input({ required: true }) isOpen = false;
  @Output() close = new EventEmitter<void>();
}