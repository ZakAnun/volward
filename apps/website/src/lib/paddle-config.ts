import { mapPaddleJsEnvironment } from './paddle-checkout';

export function paddleClientToken(): string {
  return typeof __PADDLE_CLIENT_TOKEN__ === 'string' ? __PADDLE_CLIENT_TOKEN__ : '';
}

export function paddleBuildEnv(): string {
  return typeof __PADDLE_ENV__ === 'string' ? __PADDLE_ENV__ : 'sandbox';
}

export function paddleJsEnvironment(): 'sandbox' | 'production' {
  return mapPaddleJsEnvironment(paddleBuildEnv());
}
