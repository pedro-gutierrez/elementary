start:
	@iex -S mix

build:
	@docker build -t pedrogutierrez/eventbee:latest .

push:
	@docker push pedrogutierrez/eventbee:latest

run:
	@docker run -e ELEMENTARY_ADMIN_TOKEN \
    -e ELEMENTARY_MONGO_URL \
    -e ELEMENTARY_SLACK_CLUSTER \
    -e ELEMENTARY_SLACK_ERRORS \
    -e ELEMENTARY_SLACK_EVENTS \
    -e ELEMENTARY_SLACK_TELEMETRY \
    -e ELEMENTARY_WEBROOT \
	-e LINKEDIN_CLIENT_ID \
	-e LINKEDIN_CLIENT_SECRET \
	-e FACEBOOK_CLIENT_ID \
	-e FACEBOOK_CLIENT_SECRET \
	-e GOOGLE_CLIENT_ID \
	-e GOOGLE_CLIENT_SECRET \
	-e GOOGLE_API_KEY \
	-e GITHUB_CLIENT_ID \
	-e GITHUB_CLIENT_SECRET \
	-e PAYPAL_BASE_URL \
	-e PAYPAL_CLIENT_ID \
	-e PAYPAL_CLIENT_SECRET \
	-p 4000:4000 \
    pedrogutierrez/eventbee:latest

up:
	@helm upgrade --install eventbee chart

down:
	@helm uninstall eventbee