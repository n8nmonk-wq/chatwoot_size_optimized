json.array! @clients do |client|
  json.partial! 'api/v1/models/client', formats: [:json], resource: client
end
