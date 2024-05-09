import * as ansiEscapes from 'ansi-escapes';
import * as ansiStyles from 'ansi-styles';

// TODO: Make these configuration options.
const FRAMERATE = 40;
const COLS = process.stdout.columns;
const ROWS = process.stdout.rows;
const NEW_THREAD_RATE = 120;
const THREAD_GAP = Math.ceil(ROWS * 0.5);
const MIN_THREAD_LENGTH = 4;
const MAX_THREAD_LENGTH = Math.ceil(ROWS * 0.5);
const MAX_GROW_RATE = 8;
const MIN_GROW_RATE = 2;
const MAX_FRAME = 1000000000;
const CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@#$%&*<>?:~-=+|/\\';
const COLOR = ansiStyles.green;

interface Thread {
  /** X position of thread. */
  x: number;
  /** Y position of head character. May be larger than physical number of rows if offscreen. */
  headY: number;
  /** Current head character. */
  headChar: string;
  /** Y position of tail character. May be negative if offscreen. */
  tailY: number;
  /** Rate of growth (moving the head downwards by 1) in # of frames. */
  growRate: number;
  /** Rate of shrinkage (moving the tail downwards by 1) in # of frames. */
  shrinkRate: number;
}

function randInt(minValue: number, maxValue: number) {
  return Math.floor(Math.random() * (maxValue - minValue + 1)) + minValue;
}

function randFrame(rate: number) {
  return Math.random() < 1 / rate;
}

function nthFrame(frame: number, rate: number) {
  return frame % rate === 0;
}

function randChar() {
  return CHARS.charAt(Math.floor(Math.random() * CHARS.length));
}

enum CharStyle {
  NORMAL = 'normal',
  HEAD = 'head',
}

function printChar(x: number, y: number, c: string, style: CharStyle) {
  if (x < 0 || x >= COLS || y < 0 || y >= ROWS) {
    return;
  }
  let styleOpen: string, styleClose: string;
  switch (style) {
    case CharStyle.HEAD:
      styleOpen = ansiStyles.whiteBright.open;
      styleClose = ansiStyles.whiteBright.close;
      break;
    default:
      styleOpen = COLOR.open;
      styleClose = COLOR.close;
      break;
  }
  process.stdout.write(ansiEscapes.cursorTo(x, y) + styleOpen + c + styleClose);
}

class Scene {
  private threadsByColumn: Array<Array<Thread>> = Array(COLS)
    .fill(0)
    .map(() => []);

  private frame = 0;

  private createThreads() {
    for (let x = 0; x < COLS; ++x) {
      const threads = this.threadsByColumn[x];
      if (
        threads.some(({tailY}) => tailY <= THREAD_GAP) ||
        !randFrame(NEW_THREAD_RATE)
      ) {
        continue;
      }
      const growRate = randInt(MIN_GROW_RATE, MAX_GROW_RATE);
      threads.push({
        x,
        headY: -1,
        headChar: ' ',
        tailY: -randInt(MIN_THREAD_LENGTH, MAX_THREAD_LENGTH),
        growRate,
        shrinkRate: randInt(
          growRate,
          Math.floor((growRate + MAX_GROW_RATE) / 2)
        ),
      });
    }
  }

  private cleanUpThreads() {
    for (const threads of this.threadsByColumn) {
      for (let i = 0; i < threads.length; ++i) {
        const thread = threads[i];
        if (thread.tailY > ROWS) {
          threads.splice(i, 1);
          --i;
        }
      }
    }
  }

  private growThread(thread: Thread) {
    if (thread.headY >= ROWS) {
      return;
    }
    printChar(thread.x, thread.headY, thread.headChar, CharStyle.NORMAL);
    ++thread.headY;
    thread.headChar = randChar();
    printChar(thread.x, thread.headY, thread.headChar, CharStyle.HEAD);
  }

  private shrinkThread(thread: Thread) {
    ++thread.tailY;
    printChar(thread.x, thread.tailY, ' ', CharStyle.NORMAL);
  }

  renderFrame() {
    this.createThreads();

    for (let x = 0; x < COLS; ++x) {
      const threads = this.threadsByColumn[x];
      for (const thread of threads) {
        if (nthFrame(this.frame, thread.growRate)) {
          this.growThread(thread);
        }
        if (nthFrame(this.frame, thread.shrinkRate)) {
          this.shrinkThread(thread);
        }
      }
    }

    this.cleanUpThreads();
    this.frame = (this.frame + 1) % MAX_FRAME;
  }
}

export function run() {
  const scene = new Scene();
  process.stdout.write(ansiEscapes.clearScreen + ansiEscapes.cursorHide);
  const intervalId = setInterval(
    () => scene.renderFrame(),
    Math.floor(1000 / FRAMERATE)
  );

  process.on('SIGINT', () => {
    clearInterval(intervalId);
    process.stdout.write(ansiEscapes.eraseScreen + ansiEscapes.cursorShow);
    process.exit();
  });
}

if (require.main === module) {
  run();
}
