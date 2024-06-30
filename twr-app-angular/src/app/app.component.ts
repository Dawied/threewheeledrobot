import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { MotorControllerComponent } from './motor-controller/motor-controller.component';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, MotorControllerComponent],
  templateUrl: './app.component.html',
  styleUrl: './app.component.css'
})

export class AppComponent {
  title = 'twr-app';
}
