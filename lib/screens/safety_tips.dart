import 'package:flutter/material.dart';

import '../widgets/glass.dart';

class SafetyTipsPage extends StatelessWidget {
  const SafetyTipsPage({super.key});

  static const _chapters = <List<String>>[
    [
      'Read this first',
      '''NAZA is a decision-support tool, not a driving authority, map service, emergency service, or promise of safety. Its accuracy depends on the real-world conditions around you and on the information available to the model. Weather, traffic, road work, visibility, changing signs, animals, pedestrians, mechanical problems, and events that happen after a scan may not be represented.

A Low result is never permission to take more risk. Do not speed, rush, drive aggressively, ignore a sign, or stop paying attention because the scanner reported Low. The model cannot always forecast the full risk portfolio of a trip. If the road looks or feels unsafe, slow down safely, pull over when legal, or choose another plan.''',
    ],
    [
      'The simple driving rule',
      '''Seat belts, not speeding, turn signals, and following the essential road rules are always more important than a scan result. Keep watching the road with your central and peripheral vision. Make proper stops. Wait when you are unsure. Do not rush to beat a light, merge, turn, or exit. A careful driver leaves time and space for other people to make mistakes.''',
    ],
    [
      'Before you move',
      '''• Adjust your seat, mirrors, steering wheel, and climate controls before entering traffic.
• Fasten your seat belt and make sure every passenger is buckled. Use the correct child restraint for the child’s size and follow its instructions.
• Check fuel or charge, tires, lights, wipers, mirrors, and visible warning lights.
• Put your phone away or enable a hands-free mode. Never type, scroll, or hold a phone while moving.
• Know your destination before you go. If you need to change the route, pull over safely first.
• If you are very tired, impaired, angry, or in a hurry, delay the trip or ask someone else to drive.''',
    ],
    [
      'Use a scan safely',
      '''1. Enter the road, area, or destination.
2. Run the scan while stopped or before the trip. Do not interact with the app while driving.
3. Compare the result with what you can actually see and with official signs, closures, alerts, and local rules.
4. Treat Medium or High as a reason to slow down, add space, reconsider the route, and verify conditions—not as a prediction of exactly what will happen.
5. Treat Low as “no major warning was found in this input,” not as “the road is safe.” Re-scan only when it is useful and only from a safe place.''',
    ],
    [
      'Common driving errors',
      '''The most common errors are looking at a phone, following too closely, driving faster than conditions allow, failing to check a blind spot, drifting across a lane line, rolling through a stop, turning without signaling, braking late, and assuming another driver sees you. Other frequent errors include driving while tired, entering an intersection without room to exit, passing where visibility is poor, and focusing on a destination instead of the road.

Correct them with a short routine: look far ahead, check mirrors regularly, scan the sides, signal early, check the blind spot, leave a cushion, and make smooth decisions. If you miss a turn, continue safely and reroute after stopping. Never make a sudden turn or reversal just to recover time.''',
    ],
    [
      'Space, speed, and stopping',
      '''Keep a following gap that gives you time to see, decide, and stop. Use more space at night, in rain, on gravel, near motorcycles, behind large vehicles, and whenever visibility is limited. A time-based gap is more useful than counting car lengths; increase it when conditions worsen.

Stay within the posted limit and slow further when the road, weather, traffic, or visibility calls for it. The posted limit is not a target in every condition. Look beyond the vehicle immediately ahead so you can brake smoothly. Avoid hard acceleration, late braking, and weaving between lanes. At a stop sign or red light, make a complete stop before the limit line or crosswalk and wait your turn.''',
    ],
    [
      'Intersections, turns, and lane changes',
      '''Scan left, right, and left again. Watch for people walking, bicycles, motorcycles, children, and vehicles that may run a light. Do not block an intersection. Signal early enough to give others useful notice, but remember that a signal does not give you the right of way.

For a lane change: check the mirror, signal, check the next mirror, check the blind spot with a brief glance, then move only when there is enough space. Keep the wheel steady and cancel the signal. Before turning, slow down, choose the correct lane, look through the turn, and check for a person or cyclist in the path. Never rely on a camera or sensor alone.''',
    ],
    [
      'Weather and visibility',
      '''Rain can hide standing water, reduce tire grip, and make brake response less predictable. Slow down, increase space, turn on the correct lights, and avoid sudden steering. In heavy rain or flooding, do not enter water if you cannot judge its depth or current.

At night, keep the windshield and lights clean and use high beams only when legal and when they will not glare into another driver’s eyes. In fog, slow down, use the proper low-beam or fog-light setting, and use lane markings as a guide. In snow or ice, drive gently, leave a very large gap, and avoid unnecessary trips. Pull over when visibility or traction is too poor.''',
    ],
    [
      'Work zones and unusual roads',
      '''Expect lane shifts, workers, temporary signs, uneven surfaces, stopped equipment, and sudden queues. Follow the temporary signs and flaggers even when an app shows a lower risk. Slow down before the work area, leave extra room, and do not move cones or pass a closure.

On narrow roads, hills, curves, bridges, and unfamiliar driveways, assume you may meet someone you cannot yet see. Slow before the curve, stay in your lane, and do not pass unless you have a clear legal view and enough room to finish safely.''',
    ],
    [
      'How to reduce tickets and stressful stops',
      '''The reliable way to reduce tickets is to make lawful driving automatic: obey posted speed limits, come to complete stops, signal every turn and lane change, use required lights, wear a seat belt, keep registration and insurance current, and follow parking and work-zone signs. Keep plates visible and equipment legal for your area.

Do not use a scanner result to justify a traffic violation. Avoid racing yellow lights, blocking crosswalks, using restricted lanes, tailgating, illegal phone use, unsafe passing, or aggressive gestures. If an officer stops you, pull over safely, keep your hands visible, stay calm, and follow the instructions. Local laws differ, so check your official state or local driver manual.''',
    ],
    [
      'Attention, fatigue, and passengers',
      '''Driving needs your full attention. Do not drive after using alcohol, recreational drugs, or medicine that makes you drowsy or slow. Fatigue can look like frequent yawning, missing signs, lane drift, forgetting the last few miles, or needing loud music to stay awake. Stop in a safe public place and rest; caffeine is not a substitute for sleep.

Ask passengers to keep the cabin calm. Secure pets and loose objects. Do not let conversations, food, grooming, or a loud screen pull your eyes from traffic. If a passenger needs help, pull over before dealing with it.''',
    ],
    [
      'If something goes wrong',
      '''If you feel unsafe, do not keep driving just to finish the trip. Reduce speed smoothly, use your signals, and pull over somewhere legal and visible. Turn on hazard lights when appropriate. For a tire problem, warning light, overheating, loss of visibility, or mechanical noise, stop in a safe place and call roadside assistance.

After a crash, stop, check for injuries, call emergency services when needed, move only if it is safe and required, and exchange information as local law requires. Do not use the app while handling an emergency. Call emergency services for immediate danger.''',
    ],
    [
      'A calm-driver checklist',
      '''Before moving: belt, mirrors, route, phone away.
While moving: eyes up, hands ready, space ahead, signal early, check blind spots.
At every intersection: slow, scan, yield when required, and do not block.
When conditions change: slow down, increase distance, and reassess.
When uncertain: wait. When tired: stop. When the scanner and the road disagree: trust the road and official instructions.

The goal is not to get a perfect score. The goal is to arrive with attention, patience, and enough time to make safe decisions.''',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 18),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
          child: Text(
            'Driving Manual • Safety Tips',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
        ),
        for (final chapter in _chapters)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassPanel(
              radius: 18,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chapter[0],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    chapter[1],
                    style: const TextStyle(color: Colors.white70, height: 1.42),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
