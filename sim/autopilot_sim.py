# -*- coding: utf-8 -*-
"""
Regelkreis-Simulation fuer FlightOS-Autopilot (flightos/service.lua).

Modelliert:
- Schiff mit Giertragheit (yaw inertia), Richtungsveraenderung trage nach Ruderkommando
- Drift (Geschwindigkeitsrichtung hinkt der Nase hinterher, solange gedreht wird)
- GPS: ganzzahlige Fixes alle 0.5 s (wie gps.locate in CC:Tweaked)
- Autopilot-Loop mit dt = 0.05 s (wie Service.loop mit sleep(0.05))

Zwei Regler:
- AutopilotCurrent: exakter Port der Logik aus service.lua (Stand bee82fe)
- AutopilotFixed: korrigierte Logik (bipolarer PD auf gemessener Drehrate,
  Gegenruder mit Hysterese, kein Rueckwaertsbremsen)

Konvention (wie im Lua-Code): bearing = atan2(dx, dz), heading aus Bewegungsrichtung.
"""

import math

def clamp(v, lo, hi):
    return max(lo, min(hi, v))

def wrap(a):
    return math.atan2(math.sin(a), math.cos(a))

# ---------------------------------------------------------------------------
# Konfiguration (entspricht defaults aus flightos/config.lua)
# ---------------------------------------------------------------------------
CFG = dict(
    auto_speed_max=256,
    auto_steer_max=256,
    auto_steer_kp=80,
    auto_steer_kd=15,
    auto_steer_coast_factor=0.6,
    auto_steer_hold_rate=0.04,
    auto_steer_hold_error=0.05,
    auto_steer_hold_max=5.0,
    speed_invert=False,
    steer_invert=True,
    auto_thrust_steer_mix=1.0,
)

DT = 0.05          # Autopilot-Tick (sleep(0.05))
GPS_DT = 0.5       # gps.locate Intervall (Service.gpsLoop)
ARRIVE_DIST = 3.0  # Zielradius (aus service.lua)


class Ship:
    """Sehr vereinfachtes aerostatisches Schiff."""

    def __init__(self, x, z, psi):
        self.x = x
        self.z = z
        self.psi = psi       # Nase (Bearing-Konvention: 0 = +z, pi/2 = +x)
        self.omega = 0.0     # Drehrate rad/s
        self.v = 0.0         # Fahrt m/s
        self.wiring_sign = +1  # +1: Ruder wirkt in Kommandorichtung (Inv Steer korrekt)

    def step(self, dt, steer_norm, thrust_cmd):
        # Ruder + Differentialschub -> Gierbeschleunigung mit Tragheit
        G = 0.35   # Ruderwirkung
        D = 1.00   # Gierdaempfung (Terminal-Drehrate bei Vollruder: G/D = 0.35 rad/s)
        self.omega += (G * steer_norm * self.wiring_sign - D * self.omega) * dt
        # Schub -> Fahrt
        v_target = thrust_cmd * (10.0 / 256.0)   # 256 RPM ~ 10 m/s
        self.v += (v_target - self.v) * (dt / 1.2)
        # Drift: Geschwindigkeitsrichtung weicht im Kurvenbetrieb von der Nase ab
        slip = clamp(-0.6 * self.omega, -0.3, 0.3)
        vdir = self.psi + slip
        self.x += math.sin(vdir) * self.v * dt
        self.z += math.cos(vdir) * self.v * dt
        self.psi += self.omega * dt


class GpsSim:
    """gps.locate: ganzzahlige Position, alle GPS_DT Sekunden."""

    def __init__(self, ship):
        self.ship = ship
        self.next_fix = 0.0

    def poll(self, t, d):
        if t >= self.next_fix:
            self.next_fix = t + GPS_DT
            d["x"] = float(round(self.ship.x))
            d["y"] = 64.0
            d["z"] = float(round(self.ship.z))


class BaseAutopilot:
    def __init__(self, cfg):
        self.cfg = cfg
        self.reset()

    def reset(self):
        self.prev_gps_x = None
        self.prev_gps_z = None
        self.last_heading_x = None
        self.last_heading_z = None
        self.smooth_vx = 0.0
        self.smooth_vz = 0.0
        self.current_heading = 0.0
        self.turn_rate = 0.0
        self.last_heading_update_time = None
        self.hold_active = False
        self.hold_release_err = 0.0
        self.hold_start_time = None
        self.is_moving = False
        self.start_dist = None
        self.prev_err = 0.0
        self.auto_start_time = None
        # Diagnose
        self.n_hold = 0
        self.n_err_flips = 0
        self.last_err_sign = 0
        self.full_rudder_time = 0.0
        self.n_steps = 0

    def _update_heading(self, t, cx, cz):
        """Exakter Port des GPS-Heading-Trackers aus service.lua."""
        if self.last_heading_x is None:
            self.last_heading_x = cx
            self.last_heading_z = cz
            self.smooth_vx = 0.0
            self.smooth_vz = 0.0
        if self.prev_gps_x is not None and (cx != self.prev_gps_x or cz != self.prev_gps_z):
            dxm = cx - self.last_heading_x
            dzm = cz - self.last_heading_z
            md = math.hypot(dxm, dzm)
            if md > 0.5:
                self.smooth_vx = self.smooth_vx * 0.7 + dxm * 0.3
                self.smooth_vz = self.smooth_vz * 0.7 + dzm * 0.3
                new_heading = math.atan2(self.smooth_vx, self.smooth_vz)
                if self.last_heading_update_time is not None:
                    hdt = t - self.last_heading_update_time
                    if hdt > 0.05:
                        hd = wrap(new_heading - self.current_heading)
                        self.turn_rate = self.turn_rate * 0.6 + (hd / hdt) * 0.4
                self.last_heading_update_time = t
                self.current_heading = new_heading
                self.is_moving = True
                self.last_heading_x = cx
                self.last_heading_z = cz
        self.prev_gps_x = cx
        self.prev_gps_z = cz

    def _rate_now(self, t):
        if self.last_heading_update_time is not None and (t - self.last_heading_update_time) < 1.0:
            return self.turn_rate
        return 0.0

    def _diag(self, t, dt, err, steer_speed):
        self.n_steps += 1
        if abs(steer_speed) >= 0.98 * self.cfg["auto_steer_max"]:
            self.full_rudder_time += dt
        s = 1 if err > 1e-9 else (-1 if err < -1e-9 else 0)
        if s != 0 and self.last_err_sign != 0 and s != self.last_err_sign:
            self.n_err_flips += 1
        if s != 0:
            self.last_err_sign = s

    def step(self, t, d):
        """Rueckgabe: (thrust_cmd, steer_cmd) oder None wenn angekommen/aus."""
        raise NotImplementedError


class AutopilotCurrent(BaseAutopilot):
    """Exakter Port der aktuellen Logik aus flightos/service.lua (Commit bee82fe)."""

    REVERSE = True   # False = Experiment: Rueckwaertsbremsen abgeschaltet

    def step(self, t, d):
        cfg = self.cfg
        cx, cz = d["x"], d["z"]
        if cx is None:
            return (0.0, 0.0)
        tx, tz = cfg["target_x"], cfg["target_z"]
        dx = tx - cx
        dz = tz - cz
        dist = math.hypot(dx, dz)
        if self.start_dist is None:
            self.start_dist = dist
        if dist > ARRIVE_DIST:
            if self.auto_start_time is None:
                self.auto_start_time = t
            self._update_heading(t, cx, cz)
            max_speed = cfg["auto_speed_max"]
            elapsed = t - self.auto_start_time
            accel_ramp = min(1.0, elapsed / 5.0)
            cruise_speed = max_speed * accel_ramp
            brake_dist = 100.0
            reverse_dist = 15.0 if self.REVERSE else 0.0
            if self.REVERSE and dist < reverse_dist:
                reverse_factor = (reverse_dist - dist) / reverse_dist
                base_speed = -max_speed * 0.5 * reverse_factor
            elif dist < brake_dist:
                decel_factor = (dist - reverse_dist) / (brake_dist - reverse_dist)
                base_speed = cruise_speed * max(0.15, decel_factor)
            else:
                base_speed = cruise_speed
            if cfg["speed_invert"]:
                base_speed = -base_speed
            speed = clamp(base_speed, -max_speed, max_speed)
            steer_blend = min(1.0, max(0.0, elapsed / 3.0))
            steer_speed = 0.0
            err = None
            if self.is_moving and steer_blend > 0 and (not self.REVERSE or dist > reverse_dist):
                target_h = math.atan2(dx, dz)
                err = wrap(target_h - self.current_heading)
                derr = wrap(err - self.prev_err)
                deriv = derr / DT
                self.prev_err = err
                abs_err = abs(err)
                kp_factor = (cfg["auto_steer_kp"] or 80.0) / 80.0
                kd_factor = (cfg["auto_steer_kd"] or 15.0) / 15.0
                proportional = (abs_err / 0.20) * kp_factor
                damping = abs(deriv) * kd_factor * 0.02
                turn_strength = clamp((proportional - damping) * steer_blend, 0, 1)
                rate_now = self._rate_now(t)
                coast_factor = cfg["auto_steer_coast_factor"] or 0.6
                hold_error = cfg["auto_steer_hold_error"] or 0.05
                hold_rate = cfg["auto_steer_hold_rate"] or 0.04
                hold_timeout = cfg["auto_steer_hold_max"] or 5.0
                smax = cfg["auto_steer_max"]
                if self.hold_active:
                    steer_speed = (-1 if rate_now > 0 else 1) * smax * coast_factor
                    timed_out = self.hold_start_time is not None and (t - self.hold_start_time) > hold_timeout
                    if abs_err < 0.01 or abs_err > self.hold_release_err + hold_error \
                            or abs(rate_now) < hold_rate or timed_out:
                        self.hold_active = False
                        self.hold_start_time = None
                        steer_speed = 0.0
                elif abs_err >= 0.03:
                    steer_speed = (1 if err > 0 else -1) * smax * turn_strength
                else:
                    self.hold_release_err = abs_err
                    self.hold_start_time = t
                    if abs(rate_now) >= hold_rate:
                        self.hold_active = True
                        self.n_hold += 1
                        steer_speed = (-1 if rate_now > 0 else 1) * smax * coast_factor
                    else:
                        self.hold_start_time = None
            # steer_invert ist global: Vorzeichen kollabiert mit Verdrahtung -> hier neutral
            self._diag(t, DT, err if err is not None else 0.0, steer_speed)
            return (speed, steer_speed)
        return None  # angekommen


class AutopilotFixed(BaseAutopilot):
    """Korrigierte Logik:
    - bipolarer PD-Regler: P auf Kursfehler, D auf gemessener Drehrate
    - Gegenruder-Phase mit Hysterese (Eingang >= hold_rate, Ausgang <= hold_rate/2)
    - kein Rueckwaertsbremsen mehr (Kein 180-Grad-Kurs-Sprung unter 15 m)
    """

    DAMP_REF = 0.25   # Bezugs-Drehrate fuer D-Anteil
    DAMP_GAIN = 0.5   # D-Starke
    HOLD_ZONE = 0.10  # Gegenruder nur nahe am Zielkurs aktivieren (rad)

    def step(self, t, d):
        cfg = self.cfg
        cx, cz = d["x"], d["z"]
        if cx is None:
            return (0.0, 0.0)
        tx, tz = cfg["target_x"], cfg["target_z"]
        dx = tx - cx
        dz = tz - cz
        dist = math.hypot(dx, dz)
        if self.start_dist is None:
            self.start_dist = dist
        if dist > ARRIVE_DIST:
            if self.auto_start_time is None:
                self.auto_start_time = t
            self._update_heading(t, cx, cz)
            max_speed = cfg["auto_speed_max"]
            elapsed = t - self.auto_start_time
            accel_ramp = min(1.0, elapsed / 5.0)
            cruise_speed = max_speed * accel_ramp
            brake_dist = 100.0
            steer_gate = 5.0
            # Nur noch vorwaerts bremsen, kein Rueckwaertsfahren mehr
            if dist < brake_dist:
                decel_factor = dist / brake_dist
                base_speed = cruise_speed * max(0.15, decel_factor)
            else:
                base_speed = cruise_speed
            if cfg["speed_invert"]:
                base_speed = -base_speed
            speed = clamp(base_speed, -max_speed, max_speed)
            steer_blend = min(1.0, max(0.0, elapsed / 3.0))
            steer_cmd = 0.0
            err = None
            if self.is_moving and steer_blend > 0 and dist > steer_gate:
                target_h = math.atan2(dx, dz)
                err = wrap(target_h - self.current_heading)
                abs_err = abs(err)
                rate_now = self._rate_now(t)
                kp_factor = (cfg["auto_steer_kp"] or 80.0) / 80.0
                kd_factor = (cfg["auto_steer_kd"] or 15.0) / 15.0
                coast_factor = cfg["auto_steer_coast_factor"] or 0.6
                hold_error = cfg["auto_steer_hold_error"] or 0.05
                hold_rate = cfg["auto_steer_hold_rate"] or 0.04
                hold_timeout = cfg["auto_steer_hold_max"] or 5.0
                if self.hold_active:
                    # Gegenruder halten, bis die Drehrate abgeklungen ist (Hysterese)
                    steer_cmd = -coast_factor if rate_now > 0 else coast_factor
                    timed_out = self.hold_start_time is not None and (t - self.hold_start_time) > hold_timeout
                    if abs(rate_now) <= hold_rate * 0.5 \
                            or abs_err > self.hold_release_err + hold_error or timed_out:
                        self.hold_active = False
                        self.hold_start_time = None
                else:
                    # Bipolarer PD: P auf Fehler, D auf gemessener Drehrate
                    proportional = (err / 0.20) * kp_factor
                    damping = (rate_now / self.DAMP_REF) * kd_factor * self.DAMP_GAIN
                    steer_cmd = clamp(proportional - damping, -1.0, 1.0) * steer_blend
                    if abs(steer_cmd) < 0.02:
                        steer_cmd = 0.0
                    # Gegenruder-Phase starten, wenn ohne Lenkbedarf noch gedreht wird
                    if abs_err < self.HOLD_ZONE and abs(rate_now) >= hold_rate:
                        self.hold_active = True
                        self.hold_release_err = abs_err
                        self.hold_start_time = t
                        self.n_hold += 1
                        steer_cmd = -coast_factor if rate_now > 0 else coast_factor
            steer_speed = steer_cmd * cfg["auto_steer_max"]
            self._diag(t, DT, err if err is not None else 0.0, abs(steer_speed))
            return (speed, steer_speed)
        return None  # angekommen


def run(controller_cls, label, ship_start, target, t_max=600.0, cfg_over=None):
    cfg = dict(CFG)
    cfg["target_x"] = float(target[0])
    cfg["target_z"] = float(target[1])
    if cfg_over:
        cfg.update(cfg_over)
    ship = Ship(*ship_start)
    gps = GpsSim(ship)
    ap = controller_cls(cfg)
    d = {"x": None, "y": None, "z": None}
    t = 0.0
    min_dist = float("inf")
    # erstes GPS-Fix sofort
    gps.poll(t, d)
    while t < t_max:
        out = ap.step(t, d)
        if out is None:
            return dict(label=label, arrived=True, t=t, dist_final=dist_of(ship, cfg),
                        min_dist=min_dist, hold=ap.n_hold, flips=ap.n_err_flips,
                        full_rudder=ap.full_rudder_time / max(ap.n_steps * DT, 1e-9))
        thrust_cmd, steer_cmd = out
        ship.step(DT, steer_cmd / cfg["auto_steer_max"], thrust_cmd)
        t += DT
        gps.poll(t, d)
        dist = math.hypot(cfg["target_x"] - ship.x, cfg["target_z"] - ship.z)
        min_dist = min(min_dist, dist)
    return dict(label=label, arrived=False, t=t_max, dist_final=dist_of(ship, cfg),
                min_dist=min_dist, hold=ap.n_hold, flips=ap.n_err_flips,
                full_rudder=ap.full_rudder_time / max(ap.n_steps * DT, 1e-9))


def dist_of(ship, cfg):
    return math.hypot(cfg["target_x"] - ship.x, cfg["target_z"] - ship.z)


def trace_trajectory(controller_cls, ship_start, target, t_max=240.0, every=20.0):
    """Gibt die Position alle `every` Sekunden aus, um den Kreis sichtbar zu machen."""
    cfg = dict(CFG)
    cfg["target_x"] = float(target[0])
    cfg["target_z"] = float(target[1])
    ship = Ship(*ship_start)
    gps = GpsSim(ship)
    ap = controller_cls(cfg)
    d = {"x": None, "y": None, "z": None}
    t = 0.0
    next_mark = 0.0
    print("  t[s]     x      z    dist")
    while t < t_max:
        out = ap.step(t, d)
        if out is None:
            print("  %5.1f  ANGEKOMMEN" % t)
            return
        thrust_cmd, steer_cmd = out
        ship.step(DT, steer_cmd / cfg["auto_steer_max"], thrust_cmd)
        t += DT
        gps.poll(t, d)
        if t >= next_mark:
            next_mark += every
            dist = math.hypot(cfg["target_x"] - ship.x, cfg["target_z"] - ship.z)
            print("  %5.1f  %6.1f  %6.1f  %6.1f" % (t, ship.x, ship.z, dist))


def main():
    print("=== Trajektorie IST (Szenario A, Ziel bei x=300) ===")
    trace_trajectory(AutopilotCurrent, (0.0, 0.0, 0.0), (300.0, 0.0))

    print()
    print("=== Experiment: IST-Logik ohne Rueckwaertsbremsen ===")
    class NoReverseCurrent(AutopilotCurrent):
        REVERSE = False
    for name, start, psi, target in [
        ("A: 300m, Start quer", (0.0, 0.0), 0.0, (300.0, 0.0)),
        ("C: 60m Nahbereich",  (0.0, 0.0), math.pi/2, (60.0, 0.0)),
    ]:
        r = run(NoReverseCurrent, "IST-noRev", (start[0], start[1], psi), target)
        status = "ANGEKOMMEN" if r["arrived"] else "NICHT ANGEKOMMEN"
        print("%-26s %s | t=%6.1fs  Enddistanz=%7.1fm  MinDistanz=%6.1fm  Err-Wechsel=%4d"
              % (name, status, r["t"], r["dist_final"], r["min_dist"], r["flips"]))

    print()
    scenarios = [
        # (Name, Startposition (x,z), Startrichtung psi, Ziel (x,z))
        ("A: 300m, Start quer",   (0.0, 0.0), 0.0,          (300.0, 0.0)),
        ("B: 300m, Start wegweisend", (0.0, 0.0), math.pi,  (300.0, 0.0)),
        ("C: 60m Nahbereich",     (0.0, 0.0), math.pi/2,    (60.0, 0.0)),
        ("D: diagonal 250m",      (0.0, 0.0), -math.pi/2,   (150.0, -200.0)),
    ]
    print()
    print("=== Vergleich IST vs FIX ===")
    for name, start, psi, target in scenarios:
        for cls, tag in ((AutopilotCurrent, "IST "), (AutopilotFixed, "FIX ")):
            r = run(cls, tag, (start[0], start[1], psi), target)
            status = "ANGEKOMMEN" if r["arrived"] else "NICHT ANGEKOMMEN (Kreisen?)"
            print("%-26s [%s] %s | t=%6.1fs  Enddistanz=%7.1fm  MinDistanz=%6.1fm  "
                  "Vollruder=%3.0f%%  Err-Wechsel=%4d  Hold-Eintraege=%3d"
                  % (name, tag, status, r["t"], r["dist_final"], r["min_dist"],
                     r["full_rudder"] * 100, r["flips"], r["hold"]))


if __name__ == "__main__":
    main()
