/**
 * Simple colored logger for console output
 * Uses chalk for colors
 */

const chalk = require('chalk');

class Logger {
  constructor(prefix = '') {
    this.prefix = prefix;
  }

  /**
   * Format message with optional prefix
   */
  _formatMessage(message) {
    if (this.prefix) {
      return `[${this.prefix}] ${message}`;
    }
    return message;
  }

  /**
   * Info message (blue)
   */
  info(message, ...args) {
    console.log(chalk.blue('ℹ'), this._formatMessage(message), ...args);
  }

  /**
   * Success message (green)
   */
  success(message, ...args) {
    console.log(chalk.green('✓'), this._formatMessage(message), ...args);
  }

  /**
   * Warning message (yellow)
   */
  warning(message, ...args) {
    console.log(chalk.yellow('⚠'), this._formatMessage(message), ...args);
  }

  /**
   * Error message (red)
   */
  error(message, ...args) {
    console.log(chalk.red('✗'), this._formatMessage(message), ...args);
  }

  /**
   * Debug message (gray) - only shows if DEBUG=true
   */
  debug(message, ...args) {
    if (process.env.DEBUG === 'true') {
      console.log(chalk.gray('→'), this._formatMessage(message), ...args);
    }
  }

  /**
   * Header with separator
   */
  header(message) {
    console.log('');
    console.log(chalk.bold.cyan('═'.repeat(60)));
    console.log(chalk.bold.cyan(`  ${message}`));
    console.log(chalk.bold.cyan('═'.repeat(60)));
    console.log('');
  }

  /**
   * Simple separator line
   */
  separator() {
    console.log(chalk.gray('─'.repeat(60)));
  }

  /**
   * Table output
   */
  table(data) {
    console.table(data);
  }

  /**
   * JSON output (formatted)
   */
  json(data) {
    console.log(JSON.stringify(data, null, 2));
  }

  /**
   * Custom colored message
   */
  custom(color, symbol, message, ...args) {
    console.log(chalk[color](symbol), this._formatMessage(message), ...args);
  }

  /**
   * Progress indicator
   */
  progress(message, current, total) {
    const percentage = Math.floor((current / total) * 100);
    const bar = '█'.repeat(Math.floor(percentage / 5)) + '░'.repeat(20 - Math.floor(percentage / 5));
    console.log(chalk.cyan(`${message} [${bar}] ${percentage}%`));
  }

  /**
   * Blank line
   */
  blank() {
    console.log('');
  }
}

// Create default logger instance
const defaultLogger = new Logger();

// Export both class and instance
module.exports = defaultLogger;
module.exports.Logger = Logger;