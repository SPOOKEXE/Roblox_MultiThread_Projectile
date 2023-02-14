local function lerp(a, b, c)
	return a + (b - a) * c
end

local function Quad(t, p0, p1, p2)
	local l1 = lerp(p0, p1, t)
	local l2 = lerp(p1, p2, t)
	return lerp(l1, l2, t)
end

function RecursiveBezier(t, ...)
	local Points = {...}
	if #Points == 3 then
		return Quad(t, ...)
	elseif #Points == 2 then
		return lerp(Points[1], Points[2], t)
	end

	local NthM1 = { }
	for index = 1, #Points - 2 do
		local p0 = Points[index]
		local p1 = Points[index+1]
		local p2 = Points[index+2]
		table.insert(NthM1, Quad(t, p0, p1, p2) )
	end
	return RecursiveBezier(t, unpack(NthM1))
end

return {
	QuadBezier = Quad,

	CubicBezier = function(t, p0, p1, p2, p3)
		local l1 = lerp(p0, p1, t)
		local l2 = lerp(p1, p2, t)
		local l3 = lerp(p2, p3, t)
		local a = lerp(l1, l2, t)
		local b = lerp(l2, l3, t)
		return lerp(a, b, t)
	end,

	GetSmoothBezierPath = function(points, pull_factor, steps_per)
		pull_factor = pull_factor or 0.6
		steps_per = steps_per or 0.05

		local PathPoints = { }

		local CurrentPosition = points[1]
		local currentIndex = 1
		while currentIndex + 2 <= #points do
			local startPoint = CurrentPosition--pointsArray[currentIndex]
			local midPoint = points[currentIndex + 1]
			local endPoint = points[currentIndex + 2]
			for i = steps_per, pull_factor, steps_per do
				local bezierPathPoint = Quad(i, startPoint, midPoint, endPoint)
				table.insert(PathPoints, bezierPathPoint)
				CurrentPosition = bezierPathPoint
			end
			currentIndex += 1
		end

		for i = 0, 1, steps_per do
			table.insert(PathPoints, lerp(CurrentPosition, points[#points], i) )
		end
		return PathPoints
	end,

	Recursive = RecursiveBezier,
}