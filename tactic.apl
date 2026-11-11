⍝ A GNU APL robot using generated queries on the shared core.
⍝ Clunkyard robot API 2.0.0: one core under every language, the same
⍝ answers everywhere. Facts (a call shows its arguments):
⍝ match: mode ruleset control robots is_3d tick_rate max_ticks
⍝   robot_id(slot)
⍝ clock: tick seconds remaining_ticks
⍝ arena: size gravity terrain_kind ground_height(x y)
⍝ me: health position velocity heading pitch roll angular_velocity
⍝   attitude grounded altitude applied
⍝ battery: charge capacity regen sustainable_drive compute
⍝   drive_cost(fraction)
⍝ drive: hover_lift
⍝ gun: aim_now cooldown_ticks spread max_power damage_scale
⍝   can_fire(power reserve) shot_speed(power) shot_cost(power)
⍝   reload_ticks(power) shot_damage(power) power_for_speed(speed)
⍝   power_for_flight_time(range seconds) lead(contact power)
⍝   lead_point(position velocity power)
⍝ scanner: last proximity_range reach(arc) arc_for_reach(range)
⍝ sensors: contacts nearest cues contact(slot) position_of(contact)
⍝ tracker: cue nearest_bearing_rate velocity(slot) position(slot)
⍝   last_seen(slot)
⍝ nav: zone zone.margin(point) zone.contains(point margin)
⍝   zone.distance_from(point) storm storm.margin(point)
⍝   storm.contains(point margin) storm.distance_from(point) hill
⍝   hill.margin(point) hill.contains(point margin)
⍝   hill.distance_from(point) pickups nearest_pickup(kind)
⍝   field_distance(a b)
⍝ score: me best armour
⍝ angles: normalize(degrees) angle_diff(target current)
⍝   bearing_to(from to) elevation_to(from to) direction(heading pitch)
⍝   distance(a b) clamp(value low high)
⍝ raw: number(path) text(path) has(path) flag(path) count(path) line()
⍝ Controls: drive.set(throttle turn pitch_turn)
⍝   drive.forces(thrust strafe lift yaw_torque pitch_torque roll_torque brake)
⍝   gun.aim(heading pitch) gun.fire(power) scanner.set(heading arc pitch)
⍝   tracker.configure(smoothing forget_ticks cue_ticks)
⍝   status.set(text value) raw.extra(json)
⍝ Every control argument is optional; a second call keeps what the first
⍝ set. Absent facts are your language's none. Names are snake_case here;
⍝ your language cases them its own way. Angles are degrees from the +x
⍝ axis; pitch is positive up.
⍝ Manual: https://clunkyard.com/manual#sdk
FREE←0
∇OnStart
 FREE←(CyMatchIs3d ⍬)∧0=CyVec3Z CyArenaGravity ⍬
∇
∇Z←T Steer C
 Z←CyAnglesClamp ((CyAnglesAngleDiff T C)÷45),¯1 1
∇
∇OnTurn;POS;H;P;T;Q;R;B;E;POWER;A;AH;AP;NOW;ERR;ACROSS;UP;D;TICK;STORM;ZONE;CLIMB;S
 POS←CyMePosition ⍬ ⋄ H←CyMeHeading ⍬ ⋄ P←CyMePitch ⍬ ⋄ TICK←CyClockTick ⍬
 CyDriveForcesBrake 0.2
 T←CySensorsNearest ⍬ ⋄ →(0=⍴T)/CUE
 R←CyContactRange T ⋄ B←CyContactBearing T ⋄ E←CyContactElevation T
 CyDriveThrottle (0.2 0.7 ¯0.4)[1+(R>350)+2×R<200]
 CyDriveTurn B Steer H ⋄ CyDrivePitchTurn E Steer P
 CyScannerHeading B ⋄ CyScannerArc 20 ⋄ CyScannerPitch E
 POWER←CyGunPowerForFlightTime R 1 ⋄ A←CyGunLead T,POWER
 AH←B ⋄ AP←E ⋄ →(0=⍴A)/AIM
 AH←CySolutionHeading A ⋄ AP←CySolutionPitch A
 AIM: CyGunAimHeading AH ⋄ CyGunAimPitch AP ⋄ NOW←CyGunAimNow ⍬
 →(~(3>|CyAnglesAngleDiff AH,CyDirectionHeading NOW)∧(3>|AP-CyDirectionPitch NOW)∧CyGunCanFire POWER 10)/TRACK
 CyGunFirePower POWER
 TRACK: CyStatusText 'TRACK' ⋄ CyStatusValue R ⋄ →CHECKS
 CUE: Q←CyTrackerCue ⍬ ⋄ →(0=⍴Q)/SEARCH
 B←CyAnglesBearingTo POS,CyCuePosition Q ⋄ D←CyAnglesDistance POS,CyCuePosition Q
 E←FREE×CyAnglesElevationTo POS,CyCuePosition Q ⋄ ERR←30⌊CyCueBearingError Q
 ACROSS←ERR×((5|TICK)-2)÷2 ⋄ UP←FREE×ERR×(¯1+3|⌊TICK÷5)÷2
 CyDriveThrottle 0.7 ⋄ CyDriveTurn B Steer H ⋄ CyDrivePitchTurn E Steer P
 CyScannerHeading B+ACROSS ⋄ CyScannerArc CyScannerArcForReach D+100 ⋄ CyScannerPitch E+UP
 CyStatusText 'CUE' ⋄ CyStatusValue D ⋄ →CHECKS
 SEARCH: CyDriveThrottle 0.5 ⋄ CyDriveTurn 0.33 ⋄ CyDrivePitchTurn 0 Steer P
 CyScannerHeading CyAnglesNormalize 36+CyScanHeading CyScannerLast ⍬
 CyScannerArc 40 ⋄ CyScannerPitch FREE×35×¯1+3|⌊TICK÷10 ⋄ CyStatusText 'SEARCH'
 CHECKS: →((CyBatteryCharge ⍬)≥(CyBatteryCapacity ⍬)÷4)/STORMCHECK
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
