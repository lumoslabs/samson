FROM ruby:2.2.3

RUN apt-get update && apt-get install -y wget apt-transport-https
RUN wget -qO- https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add -
RUN echo 'deb https://deb.nodesource.com/node_0.12 jessie main' > /etc/apt/sources.list.d/nodesource.list
RUN apt-get update && apt-get install -y nodejs

WORKDIR /app

# Mostly static
ADD config.ru /app/
ADD Rakefile /app/
ADD bin /app/bin
ADD public /app/public
ADD db /app/db
# deviation from main samson repo here. Do NOT copy the bootstrap ENV

# NPM
ADD package.json /app/package.json
RUN npm install

# Gems
ADD Gemfile /app/
ADD Gemfile.lock /app/
ADD vendor/cache /app/vendor/cache
ADD plugins /app/plugins
RUN bundle install --quiet --local --jobs 4 || bundle check

# Code
ADD config /app/config
ADD config/database.mysql.yml.example /app/config/database.yml
ADD app /app/app
ADD lib /app/lib

# precompile assets
RUN PRECOMPILE=1 bundle exec rake assets:clean --trace
RUN PRECOMPILE=1 bundle exec rake assets:precompile --trace

EXPOSE 9080

CMD ["bundle", "exec", "puma", "-C", "./config/puma.rb"]
