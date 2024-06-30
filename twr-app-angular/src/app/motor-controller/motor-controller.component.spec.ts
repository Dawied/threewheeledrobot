import { ComponentFixture, TestBed } from '@angular/core/testing';

import { MotorControllerComponent } from './motor-controller.component';

describe('MotorControllerComponent', () => {
  let component: MotorControllerComponent;
  let fixture: ComponentFixture<MotorControllerComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [MotorControllerComponent]
    })
    .compileComponents();
    
    fixture = TestBed.createComponent(MotorControllerComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });
});
