⍝ A GNU APL robot using generated queries on the shared core.
⍝ Bearing is earned: a scan contact's bearing is off by up to its
⍝ bearing error (degrees, a fixed share of the arc), so a wide beam finds a
⍝ robot and a narrow one aims at it. The robot narrows the beam, holds it
⍝ on the target and aims along a line fitted through its recent sightings.
⍝ Contacts within 120 units are exact.
⍝ Clunkyard robot API 2.0.0: one core under every language, the same
⍝ answers everywhere. Facts (a call shows its arguments):
⍝ match: mode ruleset control robots is_3d tick_rate max_ticks
⍝   robot_id(slot)
⍝ clock: tick seconds remaining_ticks
⍝ arena: size gravity terrain_kind ground_height(x y)
⍝ me: health position velocity heading pitch roll angular_velocity
⍝   attitude grounded altitude applied hull_mounts to_mount(heading pitch)
⍝   from_mount(heading pitch) mount_toward(point)
⍝ battery: charge capacity regen sustainable_drive compute
⍝   drive_cost(fraction)
⍝ drive: hover_lift
⍝ gun: aim_now cooldown_ticks spread max_power damage_scale
⍝   can_fire(power reserve) shot_speed(power) shot_cost(power)
⍝   reload_ticks(power) shot_damage(power) power_for_speed(speed)
⍝   power_for_flight_time(range seconds) lead(contact power)
⍝   lead_point(position velocity power)
⍝ scanner: last proximity_range reach(arc) arc_for_reach(range) is_on
⍝ sensors: contacts nearest cues contact(slot) position_of(contact)
⍝ tracker: cue nearest_bearing_rate velocity(slot) position(slot)
⍝   history(slot) last_seen(slot)
⍝ nav: zone zone.margin(point) zone.contains(point margin)
⍝   zone.distance_from(point) storm storm.margin(point)
⍝   storm.contains(point margin) storm.distance_from(point) hill
⍝   hill.margin(point) hill.contains(point margin)
⍝   hill.distance_from(point) pickups nearest_pickup(kind)
⍝   field_distance(a b)
⍝ score: me best armour
⍝ angles: normalize(degrees) angle_diff(target current)
⍝   bearing_to(from to) elevation_to(from to) direction(heading pitch)
⍝   distance(a b) to_chassis(heading pitch attitude)
⍝   from_chassis(heading pitch attitude) clamp(value low high)
⍝ raw: number(path) text(path) has(path) flag(path) count(path) line()
⍝ Controls: drive.set(throttle turn pitch_turn)
⍝   drive.forces(thrust strafe lift yaw_torque pitch_torque roll_torque brake)
⍝   gun.aim(heading pitch) gun.fire(power) scanner.set(heading arc pitch)
⍝   scanner.power(on) tracker.configure(smoothing forget_ticks cue_ticks)
⍝   status.set(text value) debug.log(line) raw.extra(json)
⍝ Every control argument is optional; a second call keeps what the first
⍝ set. Absent facts are your language's none. Names are snake_case here;
⍝ your language cases them its own way. Angles are degrees from the +x
⍝ axis; pitch is positive up.
⍝ Manual: https://clunkyard.com/manual#sdk
FREE←0
SEARCHARC←40 ⍝ degrees: sweeps the circle in half a second
HOLDWIDTH←60 ⍝ units across at the target: it stays in the beam from tick to tick
MINARC←6 ⍝ degrees: the narrowest the beam holds
WINDOW←12 ⍝ ticks of sightings the aim averages
SIGHTINGS←8 ⍝ narrow sightings in the window before a shot
LOOKEVERY←40 ⍝ ticks between looks around the target, for a nearer robot
REACQUIRE←10 ⍝ ticks to look again where a lost target was
⍝ The last target's slot, for looking again where it was lost.
SLOT←0
⍝ Dodges taken, and the tick the current one ends.
DODGES←0 ⋄ DODGEEND←0
∇OnStart
 FREE←(CyMatchIs3d ⍬)∧0=CyVec3Z CyArenaGravity ⍬
∇
∇Z←T Steer C
 Z←CyAnglesClamp ((CyAnglesAngleDiff T C)÷45),¯1 1
∇
⍝ A straight line through the narrowest of the last WINDOW ticks' sightings
⍝ (a row each: tick, source, bearing error, range error, x y z): where the
⍝ robot is now, how fast it moves, and how many sightings it rests on, or
⍝ empty for fewer than two. Each sighting is off by its bearing error; the
⍝ line averages that out.
∇Z←TICK Fit S;H;M;N;T0;DT;P
 Z←⍬ ⋄ H←CyTrackerHistory S ⋄ →(0=↑H)/0
 M←((↑H),7)⍴1↓H
 M←(M[;1]>TICK-WINDOW)⌿M
 →(2>(⍴M)[1])/0
 M←(M[;3]≤1.5×⌊/M[;3])⌿M ⍝ the narrow ones
 →(2>(⍴M)[1])/0
 N←(⍴M)[1] ⋄ T0←(+/M[;1])÷N ⋄ DT←M[;1]-T0 ⋄ P←M[;5 6 7]
 ⍝ The slope of each axis per tick (the ticks about their mean sum to zero), then its line's value now.
 Z←(((+⌿P)÷N)+(TICK-T0)×(DT+.×P)÷DT+.×DT),((DT+.×P)÷DT+.×DT)×CyMatchTickRate ⍬
 Z←Z,N
∇
∇OnTurn;POS;H;P;T;Q;R;B;E;POWER;A;AH;AP;NOW;ERR;ACROSS;UP;D;TICK;STORM;ZONE;CLIMB;S;C;LEFT;HOLD;ARC;READY;L;W
 POS←CyMePosition ⍬ ⋄ H←CyMeHeading ⍬ ⋄ P←CyMePitch ⍬ ⋄ TICK←CyClockTick ⍬
 CyDriveForcesBrake 0.2
 T←CySensorsNearest ⍬ ⋄ →(0=⍴T)/LOST
 SLOT←CyContactSlot T
 R←CyContactRange T ⋄ B←CyContactBearing T ⋄ E←CyContactElevation T
 CyDriveThrottle (0.2 0.7 ¯0.4)[1+(R>350)+2×R<200]
 CyDriveTurn B Steer H ⋄ CyDrivePitchTurn E Steer P
 ⍝ Halve the beam each tick until it is HOLDWIDTH across at the target: narrow
 ⍝ enough for a precise bearing, wide enough to keep it in. In a crowd a narrow
 ⍝ beam sees one robot: every LOOKEVERY ticks, widen it for a tick, and a nearer
 ⍝ robot it finds becomes the target.
 HOLD←MINARC⌈(360÷○1)×¯3○(HOLDWIDTH÷2)÷R
 ARC←HOLD⌈SEARCHARC⌊(CyScanArc CyScannerLast ⍬)÷2
 →(0≠LOOKEVERY|TICK)/NARROW ⋄ ARC←SEARCHARC
 NARROW: CyScannerHeading B ⋄ CyScannerArc ARC ⋄ CyScannerPitch E
 ⍝ An exact contact: CyGunLead is the intercept if the target holds course. A
 ⍝ noisy one: lead the fitted line, and fire only once it rests on enough sightings.
 POWER←CyGunPowerForFlightTime R 1 ⋄ READY←1 ⋄ A←⍬
 →(0=CyContactBearingError T)/EXACT
 L←TICK Fit SLOT ⋄ READY←SIGHTINGS≤↑¯1↑L ⋄ →(0=⍴L)/AIMED
 A←CyGunLeadPoint (L[1 2 3]),(L[4 5 6]),POWER ⋄ →AIMED
 EXACT: A←CyGunLead T,POWER
 AIMED: AH←B ⋄ AP←E ⋄ →(0=⍴A)/AIM
 AH←CySolutionHeading A ⋄ AP←CySolutionPitch A
 AIM: CyGunAimHeading AH ⋄ CyGunAimPitch AP ⋄ NOW←CyGunAimNow ⍬
 →(~READY∧(3>|CyAnglesAngleDiff AH,CyDirectionHeading NOW)∧(3>|AP-CyDirectionPitch NOW)∧CyGunCanFire POWER 10)/TRACK
 CyGunFirePower POWER
 TRACK: CyStatusText (1+READY)⊃'NARROW' 'TRACK' ⋄ CyStatusValue R ⋄ →CHECKS
 ⍝ Lost it: look again where it was last seen, widening the beam, before searching.
 LOST: →(0=SLOT)/CUE
 S←CyTrackerLastSeen SLOT ⋄ →(~CyPresent)/CUE ⋄ →(REACQUIRE<TICK-S)/CUE
 W←CyTrackerPosition SLOT ⋄ →CyPresent/WHERE ⋄ W←POS
 WHERE: B←CyAnglesBearingTo POS,W ⋄ E←FREE×CyAnglesElevationTo POS,W
 CyDriveThrottle 0.5 ⋄ CyDriveTurn B Steer H ⋄ CyDrivePitchTurn E Steer P
 CyScannerHeading B ⋄ CyScannerArc SEARCHARC⌊2×CyScanArc CyScannerLast ⍬ ⋄ CyScannerPitch E
 CyStatusText 'REACQUIRE' ⋄ →CHECKS
 CUE: Q←CyTrackerCue ⍬ ⋄ →(0=⍴Q)/SEARCH
 B←CyAnglesBearingTo POS,CyCuePosition Q ⋄ D←CyAnglesDistance POS,CyCuePosition Q
 E←FREE×CyAnglesElevationTo POS,CyCuePosition Q ⋄ ERR←30⌊CyCueBearingError Q
 ACROSS←ERR×((5|TICK)-2)÷2 ⋄ UP←FREE×ERR×(¯1+3|⌊TICK÷5)÷2
 CyDriveThrottle 0.7 ⋄ CyDriveTurn B Steer H ⋄ CyDrivePitchTurn E Steer P
 CyScannerHeading B+ACROSS ⋄ CyScannerArc CyScannerArcForReach D+100 ⋄ CyScannerPitch E+UP
 CyStatusText 'CUE' ⋄ CyStatusValue D ⋄ →CHECKS
 SEARCH: CyDriveThrottle 0.5 ⋄ CyDriveTurn 0.33 ⋄ CyDrivePitchTurn 0 Steer P
 CyScannerHeading CyAnglesNormalize 36+CyScanHeading CyScannerLast ⍬
 CyScannerArc SEARCHARC ⋄ CyScannerPitch FREE×35×¯1+3|⌊TICK÷10 ⋄ CyStatusText 'SEARCH'
 ⍝ A simple dodge: vary it, or predict the shooter. A shot heard once the last
 ⍝ dodge is over starts the next for 10 ticks.
 CHECKS: C←CySensorsCues ⍬ ⍝ a count, then 10 fields a contact, the source second
 →((TICK<DODGEEND)∨~(⊂'muzzle')∊C[3+10×¯1+⍳↑C])/DODGING
 DODGES←DODGES+1 ⋄ DODGEEND←TICK+10
 DODGING: →(TICK≥DODGEEND)/BATTERY
 ⍝ Off the line of fire: left, then right next time (turn is positive left, strafe positive right).
 LEFT←2|DODGES ⋄ →(~'forces'≡CyMatchControl ⍬)/DIRECT
 CyDriveThrottle 0.5 ⋄ CyDriveForcesStrafe ¯1*LEFT ⋄ →SIDE
 DIRECT: CyDriveThrottle 1 ⋄ CyDriveTurn ¯1*~LEFT
 SIDE: CyStatusText 'dodge:',(1+LEFT)⊃'right' 'left' ⋄ CyStatusValue DODGES
 BATTERY: →((CyBatteryCharge ⍬)≥(CyBatteryCapacity ⍬)÷4)/STORMCHECK
 CyDriveThrottle 0.5×CyDriveGet ⊂'throttle'
 STORMCHECK: STORM←CyNavStorm ⍬ ⋄ →(0=⍴STORM)/ZONECHECK
 →(¯60≥CyNavStormMargin POS)/ZONECHECK
 CyDriveThrottle 0.8 ⋄ CyDriveTurn CyAnglesClamp ((CyAnglesAngleDiff (CyAnglesBearingTo (CyStormCenter STORM),POS),H)÷30),¯1 1
 ZONECHECK: ZONE←CyNavZone ⍬ ⋄ →(0=⍴ZONE)/0
 →(60≤CyNavZoneMargin POS)/0
 CLIMB←0 ⋄ →(~'sphere'≡CyZoneShape ZONE)/ZONEGO
 CLIMB←CyAnglesElevationTo POS,CyZoneCenter ZONE
 ZONEGO: CyDriveThrottle 0.8
 CyDriveTurn CyAnglesClamp ((CyAnglesAngleDiff (CyAnglesBearingTo POS,CyZoneCenter ZONE),H)÷30),¯1 1
 CyDrivePitchTurn CyAnglesClamp ((CLIMB-P)÷30),¯1 1
∇
