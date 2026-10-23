class_name RoadSpec
## Single source of truth for highway geometry. Road runs along -Z (player drives toward -Z).
## Our carriageway is x > 0 (right-hand traffic), oncoming is x < 0, concrete median at x = 0.

const LANES := 4
const LANE_W := 3.7
const MEDIAN_HALF := 0.6          # half width of the median barrier footprint
const INNER_SHOULDER := 1.0
const OUTER_SHOULDER := 3.0
const CHUNK_LEN := 100.0          # streamed road segment length (m)
const VIEW_AHEAD := 900.0         # build road this far ahead of the player
const VIEW_BEHIND := 150.0


static func lane_x(lane: int, oncoming := false) -> float:
	var x := MEDIAN_HALF + INNER_SHOULDER + LANE_W * (lane + 0.5)
	return -x if oncoming else x


static func inner_edge() -> float:
	return MEDIAN_HALF


static func outer_edge() -> float:
	return MEDIAN_HALF + INNER_SHOULDER + LANE_W * LANES + OUTER_SHOULDER


## Lane index nearest to x on our side (clamped 0..LANES-1).
static func nearest_lane(x: float) -> int:
	var i := int(floor((absf(x) - MEDIAN_HALF - INNER_SHOULDER) / LANE_W))
	return clampi(i, 0, LANES - 1)
