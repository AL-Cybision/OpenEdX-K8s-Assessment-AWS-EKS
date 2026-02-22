import http from 'k6/http';
import { sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 20 },
    { duration: '2m', target: 60 },
    { duration: '30s', target: 0 },
  ],
};

export default function () {
  const host = __ENV.LMS_HOST;
  if (!host) {
    throw new Error('LMS_HOST env var is required');
  }
  http.get('http://lms:8000/', { headers: { Host: host } });
  sleep(1);
}
