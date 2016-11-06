-- Copyright © 2008-2015 Pioneer Developers. See AUTHORS.txt for details
-- Licensed under the terms of the GPL v3. See licenses/GPL-3.txt

-- A pirate system!
local s = CustomSystem:new('Tortuga',{'STAR_B_GIANT'})
	:govtype('NONE')
	:lawlessness(f(1,1))
	:short_desc('Pirate system')
	:long_desc([[The orbiting outpost of Tortuga was once known as Windward Forward Outpost, established in 2305 to act as the final stepping stone into new frontiers. However, as exploration started to shift elsewhere, the station became economically unfeasible and was eventually abandoned and faded from memories. These days Tortuga it a place of legends, and tales about space buccaneers and ships vanishing mysteriously.]])
	:seed(1230)

local tortuga = CustomSystemBody:new('Tortuga', 'STAR_B_GIANT')
	:radius(f(627,100))
	:mass(f(833,100))
	:temp(23440)

local helium = CustomSystemBody:new('Helium', 'PLANET_GAS_GIANT')
	:seed(1230)
	:radius(f(1118,100))
	:mass(f(2831,1))
	:temp(465)
	:semi_major_axis(f(11332,10000))
	:eccentricity(f(933,10000))
	:inclination(math.deg2rad(3.21))
	:rotation_period(f(410,1000))
	:axial_tilt(fixed.deg2rad(f(103,100)))
	-- :metallicity(f(7,10))
	-- :volcanicity(f(3,10))
	:atmos_density(f(32,100))
	-- :atmos_oxidizing(f(2,10))
	-- :ocean_cover(f(3,10))
        -- :ice_cover(f(2,100))
-- :orbital_phase_at_start(fixed.deg2rad(f(138,1)))

local helium_moons =
	{
	CustomSystemBody:new('Chard', 'PLANET_ASTEROID')
		:seed(1231)
		:radius(f(150,1000))
		:mass(f(145,100000000000000))
		:temp(465)
		:semi_major_axis(f(2104,1000000))
		:eccentricity(f(2,100))
		:inclination(math.deg2rad(24))
		:rotation_period(f(543,1000))
		:metallicity(f(12,100))
		:volcanicity(f(0,1))
		:atmos_density(f(0,1))
		:atmos_oxidizing(f(0,1))
		:ocean_cover(f(0,1))
		:ice_cover(f(0,1)),
	CustomSystemBody:new('Hektor', 'PLANET_TERRESTRIAL')
		:seed(1232)
		:radius(f(105,1000))
		:mass(f(1,1000))
		:temp(792)
		:semi_major_axis(f(3310,1000000))
		:eccentricity(f(845,10000))
		:inclination(math.deg2rad(1.3))
		:rotation_period(f(1245,1000))
		:metallicity(f(598,100))
		:volcanicity(f(245,100))
		:atmos_density(f(143,100))
		:atmos_oxidizing(f(13,10))
		:ocean_cover(f(2,100))
		:ice_cover(f(0,1)),
		{
		CustomSystemBody:new('Gotham', 'STARPORT_SURFACE')
--			:latitude(math.deg2rad(9.2))
		--			:longitude(math.deg2rad(45.7))
			:latitude(math.deg2rad(172))
			:longitude(math.deg2rad(20))
	}
	}

local nuhn = CustomSystemBody:new('Nuhn', 'PLANET_TERRESTRIAL')
	:seed(1233)
	:radius(f(2367,100))
	:mass(f(4598,1))
	:temp(7)
	:semi_major_axis(f(198944,10000))
	:eccentricity(f(745,10000))
	:inclination(math.deg2rad(1.09))
	:rotation_period(f(210,1))
	:axial_tilt(fixed.deg2rad(f(101,100)))
	:metallicity(f(9,10))
	:volcanicity(f(0,1))
	:atmos_density(f(98,100))
	:atmos_oxidizing(f(4,10))
	:ocean_cover(f(0,1))
	:ice_cover(f(73,100))



s:bodies(tortuga, {helium, helium_moons, nuhn})

-- s:bodies(tortuga, {})


-- todo: place it somewhere.
s:add_to_sector(1,0,0,v(0.007,0.260,0.060))

-- TODO: have a world: Arkona, Threepwood
-- Zaporizhian Sich var öst-europas piratfäste  https://en.wikipedia.org/wiki/Zaporizhian_Sich
-- station: Port Royal -> Port Regal
