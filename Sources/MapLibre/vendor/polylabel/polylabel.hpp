// mapbox::polylabel (https://github.com/mapbox/polylabel, vendor/polylabel in
// maplibre-native at ios-v7.0.0) on plain structs instead of
// mapbox::geometry, which this package does not vendor. The algorithm and its
// floating-point operations are unchanged, so results are identical.
// ISC License; see LICENSE.

#pragma once

#include <algorithm>
#include <cmath>
#include <limits>
#include <queue>
#include <vector>

namespace mapbox {

namespace polylabel_detail {

struct Point {
    double x;
    double y;
};

using Ring = std::vector<Point>;
using Polygon = std::vector<Ring>;

// get squared distance from a point to a segment
inline double getSegDistSq(const Point& p, const Point& a, const Point& b) {
    auto x = a.x;
    auto y = a.y;
    auto dx = b.x - x;
    auto dy = b.y - y;

    if (dx != 0 || dy != 0) {

        auto t = ((p.x - x) * dx + (p.y - y) * dy) / (dx * dx + dy * dy);

        if (t > 1) {
            x = b.x;
            y = b.y;

        } else if (t > 0) {
            x += dx * t;
            y += dy * t;
        }
    }

    dx = p.x - x;
    dy = p.y - y;

    return dx * dx + dy * dy;
}

// signed distance from point to polygon outline (negative if point is outside)
inline double pointToPolygonDist(const Point& point, const Polygon& polygon) {
    bool inside = false;
    auto minDistSq = std::numeric_limits<double>::infinity();

    for (const auto& ring : polygon) {
        for (std::size_t i = 0, len = ring.size(), j = len - 1; i < len; j = i++) {
            const auto& a = ring[i];
            const auto& b = ring[j];

            if ((a.y > point.y) != (b.y > point.y) &&
                (point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x)) inside = !inside;

            minDistSq = std::min(minDistSq, getSegDistSq(point, a, b));
        }
    }

    return (inside ? 1 : -1) * std::sqrt(minDistSq);
}

struct Cell {
    Cell(const Point& c_, double h_, const Polygon& polygon)
        : c(c_),
          h(h_),
          d(pointToPolygonDist(c, polygon)),
          max(d + h * std::sqrt(2))
        {}

    Point c; // cell center
    double h; // half the cell size
    double d; // distance from cell center to polygon
    double max; // max distance to polygon within a cell
};

// get polygon centroid
inline Cell getCentroidCell(const Polygon& polygon) {
    double area = 0;
    Point c { 0, 0 };
    const auto& ring = polygon.at(0);

    for (std::size_t i = 0, len = ring.size(), j = len - 1; i < len; j = i++) {
        const Point& a = ring[i];
        const Point& b = ring[j];
        auto f = a.x * b.y - b.x * a.y;
        c.x += (a.x + b.x) * f;
        c.y += (a.y + b.y) * f;
        area += f * 3;
    }

    return Cell(area == 0 ? ring.at(0) : Point{c.x / area, c.y / area}, 0, polygon);
}

} // namespace polylabel_detail

inline polylabel_detail::Point polylabel(const polylabel_detail::Polygon& polygon, double precision = 1) {
    using namespace polylabel_detail;

    // find the bounding box of the outer ring (mapbox::geometry::envelope)
    const double infinity = std::numeric_limits<double>::infinity();
    Point min { infinity, infinity };
    Point max { -infinity, -infinity };
    for (const auto& point : polygon.at(0)) {
        if (min.x > point.x) min.x = point.x;
        if (min.y > point.y) min.y = point.y;
        if (max.x < point.x) max.x = point.x;
        if (max.y < point.y) max.y = point.y;
    }

    const Point size {
        max.x - min.x,
        max.y - min.y
    };

    const double cellSize = std::min(size.x, size.y);
    double h = cellSize / 2;

    // a priority queue of cells in order of their "potential" (max distance to polygon)
    auto compareMax = [] (const Cell& a, const Cell& b) {
        return a.max < b.max;
    };
    using Queue = std::priority_queue<Cell, std::vector<Cell>, decltype(compareMax)>;
    Queue cellQueue(compareMax);

    if (cellSize == 0) {
        return min;
    }

    // cover polygon with initial cells
    for (double x = min.x; x < max.x; x += cellSize) {
        for (double y = min.y; y < max.y; y += cellSize) {
            cellQueue.push(Cell({x + h, y + h}, h, polygon));
        }
    }

    // take centroid as the first best guess
    auto bestCell = getCentroidCell(polygon);

    // special case for rectangular polygons
    Cell bboxCell(Point{min.x + size.x / 2.0, min.y + size.y / 2.0}, 0, polygon);
    if (bboxCell.d > bestCell.d) {
        bestCell = bboxCell;
    }

    while (!cellQueue.empty()) {
        // pick the most promising cell from the queue
        auto cell = cellQueue.top();
        cellQueue.pop();

        // update the best cell if we found a better one
        if (cell.d > bestCell.d) {
            bestCell = cell;
        }

        // do not drill down further if there's no chance of a better solution
        if (cell.max - bestCell.d <= precision) continue;

        // split the cell into four cells
        h = cell.h / 2;
        cellQueue.push(Cell({cell.c.x - h, cell.c.y - h}, h, polygon));
        cellQueue.push(Cell({cell.c.x + h, cell.c.y - h}, h, polygon));
        cellQueue.push(Cell({cell.c.x - h, cell.c.y + h}, h, polygon));
        cellQueue.push(Cell({cell.c.x + h, cell.c.y + h}, h, polygon));
    }

    return bestCell.c;
}

} // namespace mapbox
