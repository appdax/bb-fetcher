FROM alpine:3.4
MAINTAINER Sebastian Katzer "katzer.sebastian@googlemail.com"

ENV BUILD_PACKAGES ruby-dev libffi-dev libxslt-dev libxml2-dev gcc make libc-dev
ENV RUBY_PACKAGES ruby git curl ruby-io-console

RUN apk update && \
    apk add --no-cache $BUILD_PACKAGES && \
    apk add --no-cache $RUBY_PACKAGES && \
    gem install bundler --no-ri --no-rdoc

ENV APP_HOME /usr/app/
RUN mkdir $APP_HOME
WORKDIR $APP_HOME

COPY Gemfile $APP_HOME
COPY Gemfile.lock $APP_HOME
RUN bundle install --path vendor/bundle --no-cache --without development

COPY . $APP_HOME

CMD ["bundle", "exec", "rspec", "spec", "--fail-fast", "--failure-exit-code", "1"]
