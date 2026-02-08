import fs from 'fs';
import path from 'path';

export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
}

interface LogEntry {
  timestamp: string;
  level: string;
  category: string;
  message: string;
  data?: Record<string, unknown>;
}

class Logger {
  private logDir: string;
  private logLevel: LogLevel;
  private logFile: string;

  constructor() {
    this.logDir = path.resolve(__dirname, '../logs');
    this.logLevel = LogLevel.INFO;

    // 로그 디렉토리 생성
    if (!fs.existsSync(this.logDir)) {
      fs.mkdirSync(this.logDir, { recursive: true });
    }

    // 일별 로그 파일
    const date = new Date().toISOString().split('T')[0];
    this.logFile = path.join(this.logDir, `keeper-${date}.log`);
  }

  setLevel(level: LogLevel): void {
    this.logLevel = level;
  }

  private formatEntry(entry: LogEntry): string {
    const dataStr = entry.data ? ` | ${JSON.stringify(entry.data)}` : '';
    return `[${entry.timestamp}] [${entry.level}] [${entry.category}] ${entry.message}${dataStr}`;
  }

  private write(level: LogLevel, levelStr: string, category: string, message: string, data?: Record<string, unknown>): void {
    if (level < this.logLevel) return;

    const entry: LogEntry = {
      timestamp: new Date().toISOString(),
      level: levelStr,
      category,
      message,
      data,
    };

    const formatted = this.formatEntry(entry);

    // 콘솔 출력
    const colors: Record<string, string> = {
      DEBUG: '\x1b[36m',  // Cyan
      INFO: '\x1b[32m',   // Green
      WARN: '\x1b[33m',   // Yellow
      ERROR: '\x1b[31m',  // Red
    };
    const reset = '\x1b[0m';
    console.log(`${colors[levelStr] || ''}${formatted}${reset}`);

    // 파일 저장
    fs.appendFileSync(this.logFile, formatted + '\n');
  }

  debug(category: string, message: string, data?: Record<string, unknown>): void {
    this.write(LogLevel.DEBUG, 'DEBUG', category, message, data);
  }

  info(category: string, message: string, data?: Record<string, unknown>): void {
    this.write(LogLevel.INFO, 'INFO', category, message, data);
  }

  warn(category: string, message: string, data?: Record<string, unknown>): void {
    this.write(LogLevel.WARN, 'WARN', category, message, data);
  }

  error(category: string, message: string, data?: Record<string, unknown>): void {
    this.write(LogLevel.ERROR, 'ERROR', category, message, data);
  }

  // 메트릭 로깅 (별도 파일)
  metric(name: string, value: number, tags?: Record<string, string>): void {
    const metricsFile = path.join(this.logDir, 'metrics.jsonl');
    const entry = {
      timestamp: new Date().toISOString(),
      name,
      value,
      tags: tags || {},
    };
    fs.appendFileSync(metricsFile, JSON.stringify(entry) + '\n');
  }
}

export const logger = new Logger();
