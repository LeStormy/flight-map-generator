require 'csv'
require 'json'
require 'net/http'
require 'uri'

# --- SETTINGS ---
width = 2520.631
height = 1260.315
map_file = "world.svg"
flights_file = "flights.json"
airports_file = "airports.csv"
cities_file = "cities.json"

# --- PROJECTION FUNCTION ---
def project(lat, lon, width, height)
  x = ((lon + 180) / 360.0) * width
  y = ((90 - lat) / 180.0) * height
  [x.round(2), y.round(2)]
end

# --- LOAD AIRPORT COORDINATES ---
airport_coords = {}
iata_coords = {}
CSV.foreach(airports_file, headers: true) do |row|
  iata = row["iata"]
  lat = row["latitude"]&.to_f
  lon = row["longitude"]&.to_f
  if iata && lat && lon
    airport_coords[iata] = [lat, lon]
    iata_coords[iata] = { lat: lat, lon: lon }
  end
end

# --- LOAD FLIGHTS JSON ---
flights = JSON.parse(File.read(flights_file), symbolize_names: true)

# --- LOAD WORLD MAP SVG ---
base_svg = File.read(map_file)

# --- USED AIRPORTS ---
used_airports = flights.flat_map { |f| [f[:from], f[:to]] }.uniq

# --- CITY NAMES ---
airport_cities = JSON.parse(File.read(cities_file))

# --- DRAW FLIGHT PATHS ---
def flight_path(from, to, width, height)
  x1, y1 = project(*from, width, height)
  x2, y2 = project(*to, width, height)
  cx, cy = (x1 + x2) / 2, (y1 + y2) / 2 - 50
  %Q(<path d="M #{x1},#{y1} Q #{cx},#{cy} #{x2},#{y2}" stroke="#6B6BFF" stroke-width="2.5" fill="none" opacity="0.8" />)
end

flight_paths = flights.map do |flight|
  from = airport_coords[flight[:from]]
  to = airport_coords[flight[:to]]
  next unless from && to
  flight_path(from, to, width, height)
end.compact.join("\n")

# --- LABEL COLLISION DETECTION ---
excluded_labels = File.read("departure_airports.txt").split(" ").map(&:strip).reject(&:empty?)
placed_labels = []

def overlaps?(a, b, pad = 1)
  ax1, ay1, ax2, ay2 = a
  bx1, by1, bx2, by2 = b
  ax1 -= pad; ay1 -= pad; ax2 += pad; ay2 += pad
  !(ax2 < bx1 || ax1 > bx2 || ay2 < by1 || ay1 > by2)
end

def find_label_position(x, y, text_width = 18, text_height = 12, placed_labels = [])
  offsets = [
    [5, -5],                        # top-right
    [5, 15],                        # bottom-right
    [-text_width + 5, -5],          # top-left (was -text_width - 5)
    [-text_width + 5, 15],          # bottom-left
    [10, 5],                        # right
    [-text_width + 5, 5],           # left (was -text_width - 5)
    [-text_width / 2, -10],         # above
    [-text_width / 2, 20],          # below
  ]

  offsets.each do |dx, dy|
    x1 = x + dx
    y1 = y + dy - text_height
    x2 = x1 + text_width
    y2 = y1 + text_height
    box = [x1, y1, x2, y2]
    unless placed_labels.any? { |b| overlaps?(box, b) }
      return [dx, dy, box]
    end
  end

  nil # No valid position found
end

# --- DRAW AIRPORT DOTS + LABELS ---
airport_labels = used_airports.map do |code|
  coords = airport_coords[code]
  next unless coords
  x, y = project(*coords, width, height)
  dot = %Q(<circle cx="#{x}" cy="#{y}" r="3" fill="orange" stroke="black" stroke-width="0.5" />)

  if excluded_labels.include?(code)
    dot
  else
    label_data = find_label_position(x, y, 30, 10, placed_labels)
    if label_data
      dx, dy, box = label_data
      placed_labels << box
      label = %Q(<rect x="#{x + dx}" y="#{y + dy -9}" width="19" height="10" fill="#111" opacity="0.7" /><text x="#{x + dx}" y="#{y + dy}" font-size="10" fill="#FFFFFF" font-weight="bold" font-family="monospace">#{code}</text>)
      "#{dot}\n#{label}"
    else
      dot # fallback: show only the dot
    end
  end
end.compact.join("\n")

# --- FLIGHT STATS ---
total_flights = flights.size
flights_per_year = flights.group_by { |flight| flight[:date].split("/").last.to_i }
flights_per_destination = flights.group_by { |flight| flight[:to] }.sort_by { |k, v| [-v.size, k] }

# --- HAVERSINE DISTANCE ---
def haversine(lat1, lon1, lat2, lon2)
  rad = Math::PI / 180.0
  rkm = 6371
  dlat = (lat2 - lat1) * rad
  dlon = (lon2 - lon1) * rad
  lat1 *= rad
  lat2 *= rad
  a = Math.sin(dlat/2)**2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dlon/2)**2
  c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  rkm * c
end

flight_distance_km = flights.map do |flight|
  from = airport_coords[flight[:from]]
  to = airport_coords[flight[:to]]
  next unless from && to
  [flight, haversine(from[0], from[1], to[0], to[1]).round]
end.compact

shortest_flight_distance_km = flight_distance_km.min_by { |_, distance| distance }
longest_flight_distance_km = flight_distance_km.max_by { |_, distance| distance }

# --- CORNER LABEL (UPPER-LEFT) ---
corner_label = %Q(
  <rect x="10" y="10" width="280" height="#{flights_per_year.size * 20 + 60 + 80}" fill="#111" opacity="0.7" rx="8" />
  <text x="25" y="38" font-size="20" fill="white" font-family="monospace">
    Total Flights: #{total_flights}
  </text>
  #{flights_per_year.map.with_index do |(year, year_flights), i|
    y = 60 + 20 * (i + 1)
    %{<text x="25" y="#{y}" font-size="16" fill="white" font-family="monospace">#{year}: #{year_flights.size}</text>}
  end.join("")}
  <text x="25" y="#{60 + 20 * (flights_per_year.size + 2)}" font-size="16" fill="white" font-family="monospace">
    Shortest: #{shortest_flight_distance_km[1]} km (#{shortest_flight_distance_km[0][:from]}→#{shortest_flight_distance_km[0][:to]})
  </text>
  <text x="25" y="#{60 + 20 * (flights_per_year.size + 3)}" font-size="16" fill="white" font-family="monospace">
    Longest: #{longest_flight_distance_km[1]} km (#{longest_flight_distance_km[0][:from]}→#{longest_flight_distance_km[0][:to]})
  </text>
)

# --- DESTINATION LABELS (UPPER-RIGHT) ---
departure_airports = excluded_labels
destination_labels = flights_per_destination
  .reject { |k, _| departure_airports.include?(k) }
  .map.with_index do |(destination, destination_flights), i|
    %Q(<text x="#{width - 285}" y="#{120 + 20 * (i + 1)}" font-size="16" fill="white" font-family="monospace">#{destination_flights.size.to_s.rjust(2, '0')} x #{destination} (#{airport_cities[destination]})</text>)
  end

corner_label += %Q(
  <rect x="#{width - 300}" y="10" width="285" height="#{destination_labels.size * 20 + 60 + 120}" fill="#111" opacity="0.7" rx="8" />
  <text x="#{width - 285}" y="38" font-size="20" fill="white" font-family="monospace">
    Destinations
  </text>
  <text x="#{width - 285}" y="58" font-size="16" fill="white" font-family="monospace">
    Excludes known
  </text>
  <text x="#{width - 285}" y="78" font-size="16" fill="white" font-family="monospace">
    departure airports
  </text>
  <text x="#{width - 285}" y="98" font-size="12" fill="white" font-family="monospace">
    (#{departure_airports.join(", ")})
  </text>
  #{destination_labels.join("")}
  <text x="#{width - 285}" y="#{140 + 20 * (destination_labels.size + 1)}" font-size="16" fill="white" font-family="monospace">
    Total: #{destination_labels.size}
  </text>
)

# --- FINAL SVG ---
final_svg = base_svg.sub("</svg>", "#{flight_paths}\n#{airport_labels}\n#{corner_label}\n</svg>")

# --- OUTPUT ---
File.write("flight_map_with_base.svg", final_svg)
puts "✅ Flight map saved to flight_map_with_base.svg"
