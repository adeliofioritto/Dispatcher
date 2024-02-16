#Build node image from Node Docker Hub
FROM node:alpine3.10

RUN apk add --no-cache tzdata

ENV TZ=Europe/Rome

#Make app directory in container
RUN mkdir /app

#Identify working directory
WORKDIR /app

#Copy package
COPY package.json /app

#Install rpm packages from package.json
RUN npm install

#Copy over app to app folder
COPY . /app 

#Start app 
CMD ["node", "start.js"]