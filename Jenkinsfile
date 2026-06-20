pipeline{
    agent any
    parameters{
        string(name: 'BACKEND_VERSION', defaultValue: "latest", description: 'Tag for the Backend Docker image')
        String(name: 'FRONTEND_VERSION', defaultValue: "latest", description: 'Tag for the Frontend Docker image')
    }
    environment {
        // Define your Docker Hub repository and image tags
        APP_SERVER = "98.92.205.84" // Replace with your actual app server hostname
        //API_URL = "http://
    }
    stages{
        stage('Trigger Downstream Pipelines'){
            parallel{
                stage('Trigger Backend Pipeline'){
                    steps{
                        build job: 'backend_pipeline', parameters: [string(name: 'VERSION', value: params.BACKEND_VERSION)]
                        wait: true // Waits for the backend pipeline to complete before proceeding to the next stage
                    }
                }
                stage('Trigger Frontend Pipeline'){
                    steps{
                        build job: 'frontend_pipeline', parameters: [string(name: 'VERSION', value: params.FRONTEND_VERSION)]
                        wait: true // Waits for the frontend pipeline to complete before proceeding to the next stage
                    }
                }
            }
        }
        stage('Deploy to APP Server'){
            steps{
                script{
                    withCredentials([sshUserPrivateKey(credentialsId: 'appserverkey', keyFileVariable: 'SSH_KEY', usernameVariable: 'SSH_USER')]) {
                        sh '''
                            echo "copying dokcer-compose file to deploymenet server"
                         scp -i "$SSH_KEY" -o StrictHostKeyChecking=no docker-compose-build.yaml ${SSH_USER}@${APP_SERVER}:~/docker-compose.yaml
                         ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ${SSH_USER}@${APP_SERVER} << 'ENDSSH'
                            export DB_HOST="dev-postgres.cknc7nre3tg3.us-east-1.rds.amazonaws.com"
                            export DB_PORT=5432
                            export APP_PORT=3000
                            export DB_USER="dbadmin"
                            export DB_NAME="dev-postgres"
                            export DB_PASSWORD="s3cr3t#123"
                            docker compose down
                            sleep 10 
                            docker compose up -d
                        '''
                    }
                }
            }
        }
    }
}
