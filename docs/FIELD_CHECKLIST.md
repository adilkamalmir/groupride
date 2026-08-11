# Multi-device field checklist

Use 2–3 phones on the same Wi‑Fi as the Mac running the API.

## Prep

- [ ] API healthy at `http://<mac-lan-ip>:5080/health`
- [ ] Each device builds with `--dart-define=API_BASE=http://<mac-lan-ip>:5080`
- [ ] Location permission granted (When In Use / Always for live ride)
- [ ] Log in as leader / sweep / rider seed accounts (or register new)

## Ride organization

- [ ] Leader creates a ride with meet + stops
- [ ] Invite QR / link / share sheet opens on another device
- [ ] Join shows countdown, meet point, attendee list
- [ ] Leader assigns Sweep

## Live cohesion

- [ ] Leader starts ride → all open live map
- [ ] Markers appear for each rider within ~10s
- [ ] Status colors update (Riding / Stopped / Fuel / Emergency)
- [ ] One rider walks/drives >500m away for >45s → everyone gets split alert
- [ ] Leader receives regroup suggestion with a place name
- [ ] Split rider taps **Rejoin Group** → Apple Maps opens toward group
- [ ] Rider returns → rejoined alert

## Safety & fuel

- [ ] Rider taps **Need Help** → group sees name + location
- [ ] Bike profiles set → fuel banner appears when remaining range ≤ 40 km

## Timeline

- [ ] Leader ends ride
- [ ] Timeline shows distance, duration, stops, attendance

## Offline buffer

- [ ] Enable airplane mode briefly during live ride
- [ ] Disable airplane mode → buffered pings flush (buf counter clears)
