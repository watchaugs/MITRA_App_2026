// ═══════════════════════════════════════════════════════════════════════════
// MITRA AR — Touch gesture controller  (hand-written, editable)
//
// Translates raw touch events into three clean callbacks the engine applies to
// the model. Confirmed gesture set:
//   • 1 finger  drag          → onDrag(dx, dz)   slide on the ground plane
//   • 2 finger  twist/h-swipe → onRotate(rad)    spin about vertical axis
//   • 2 finger  pinch         → onScale(factor)  resize
//
// Design notes:
// - We decide "1-finger vs 2-finger" per gesture by how many touches are down.
// - For 2-finger we compute BOTH the rotation (angle change between the two
//   fingers, i.e. a twist) AND the horizontal-swipe rotation (both fingers
//   moving sideways together), and feed whichever dominates — so a twist OR a
//   two-finger horizontal swipe both rotate, matching the product spec, without
//   fighting the pinch-scale.
// - Pinch (distance change) always drives scale, independent of rotation.
// ═══════════════════════════════════════════════════════════════════════════

export class GestureController {
  constructor(el, handlers) {
    this.el = el;
    this.on = handlers || {};
    this._touches = new Map();     // id -> {x, y}
    this._prev = null;             // previous 2-finger frame snapshot

    this._onStart = this._start.bind(this);
    this._onMove = this._move.bind(this);
    this._onEnd = this._end.bind(this);

    el.addEventListener('touchstart', this._onStart, { passive: false });
    el.addEventListener('touchmove', this._onMove, { passive: false });
    el.addEventListener('touchend', this._onEnd, { passive: false });
    el.addEventListener('touchcancel', this._onEnd, { passive: false });
  }

  dispose() {
    const el = this.el;
    el.removeEventListener('touchstart', this._onStart);
    el.removeEventListener('touchmove', this._onMove);
    el.removeEventListener('touchend', this._onEnd);
    el.removeEventListener('touchcancel', this._onEnd);
    this._touches.clear();
    this._prev = null;
  }

  _snapshot() {
    const pts = [...this._touches.values()];
    if (pts.length < 2) return null;
    const a = pts[0], b = pts[1];
    const cx = (a.x + b.x) / 2;
    const cy = (a.y + b.y) / 2;
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const dist = Math.hypot(dx, dy) || 1;
    const angle = Math.atan2(dy, dx);  // radians between the two fingers
    return { cx, cy, dist, angle };
  }

  _start(e) {
    e.preventDefault();
    for (const t of e.changedTouches) {
      this._touches.set(t.identifier, { x: t.clientX, y: t.clientY });
    }
    this._prev = this._snapshot();        // null when <2 fingers
    this._single = this._touches.size === 1
      ? this._firstTouchXY() : null;
  }

  _firstTouchXY() {
    const p = [...this._touches.values()][0];
    return p ? { x: p.x, y: p.y } : null;
  }

  _move(e) {
    e.preventDefault();
    // Update stored positions
    for (const t of e.changedTouches) {
      if (this._touches.has(t.identifier)) {
        this._touches.set(t.identifier, { x: t.clientX, y: t.clientY });
      }
    }

    const n = this._touches.size;

    // ── 1 finger: drag on the ground plane ──────────────────────────────────
    if (n === 1 && this._single) {
      const p = this._firstTouchXY();
      if (p) {
        const dx = p.x - this._single.x;   // screen X  → world X (left/right)
        const dy = p.y - this._single.y;   // screen Y  → world Z (near/far)
        // Moving the finger UP the screen (dy negative) pushes the model AWAY
        // (−Z). Moving down pulls it NEARER (+Z). Feels natural on a floor.
        if (this.on.onDrag) this.on.onDrag(dx, dy);
        this._single = p;
      }
      return;
    }

    // ── 2 fingers: rotate (twist OR horizontal swipe) + pinch scale ─────────
    if (n >= 2) {
      const cur = this._snapshot();
      if (cur && this._prev) {
        // Rotation from twist: change in the angle between the two fingers.
        let dAngle = cur.angle - this._prev.angle;
        // Normalise to [-π, π] so a wrap doesn't spin the model wildly.
        if (dAngle > Math.PI) dAngle -= 2 * Math.PI;
        if (dAngle < -Math.PI) dAngle += 2 * Math.PI;

        // Rotation from a two-finger HORIZONTAL swipe: the pair's centre moving
        // sideways. Convert horizontal centre travel into a rotation so a flat
        // two-finger swipe also spins the model (matches the product spec).
        const swipeDx = cur.cx - this._prev.cx;
        const swipeRot = swipeDx * 0.005;   // tune: rad per px of centre travel

        // Use whichever rotation is larger in magnitude this frame, so a
        // deliberate twist and a deliberate swipe both work without doubling up.
        const rot = Math.abs(dAngle) > Math.abs(swipeRot) ? dAngle : swipeRot;
        if (rot && this.on.onRotate) this.on.onRotate(rot);

        // Pinch scale: ratio of finger distance this frame vs last.
        const factor = cur.dist / (this._prev.dist || cur.dist);
        if (factor && Math.abs(factor - 1) > 0.001 && this.on.onScale) {
          this.on.onScale(factor);
        }
      }
      this._prev = cur;
      return;
    }
  }

  _end(e) {
    for (const t of e.changedTouches) this._touches.delete(t.identifier);
    // Re-baseline so the next gesture starts clean.
    this._prev = this._snapshot();
    this._single = this._touches.size === 1 ? this._firstTouchXY() : null;
  }
}
