# KarmaBar
Personal addon for World of Warcraft to make it a bit easier to optimize a particularly convoluted ability.

Touch of Karma is supposedly a defensive ability available to monks. The primary function is to grant the monk a shield which absorbs up to 50% of their max health in damage over the next 10 seconds.
In practice, it is ALSO an offensive ability. 70% of the absorbed damage is redirected to an enemy target. Hence, Karma. 

What's so complicated about it? Well, the buff tooltip doesn't tell you how much shield is left. 
The debuff on the enemy target tells you how much damage is being redirected, but even if you can instantly do the mental math for "X is 70% of what?", it doesn't help.
The debuff is a DoT (a Damage over Time effect) which spreads each bit of damage over the next 6 seconds from the instant it was absorbed. So, that DoT's magnitude is constantly shifting as each instance of redirected damage gets added or times out.

In short, nothing in the native UI allows you to know how much damage the shield has already blocked (and, indirectly, how much more damage you could potentially redirect by INTENTIONALLY getting hit).
Karma Bar is my personal solution to that, mostly as an excuse for a fun little delve into Lua. 
While Touch of Karma's shield remains, a simple graphic reports the remaining shield amount in the center of the screen. Simple as that. 
