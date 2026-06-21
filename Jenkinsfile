pipeline {
    agent any
    parameters {
        string(name: 'BACKEND_VERSION', defaultValue: "latest", description: 'Tag for the Backend Docker image')
        string(name: 'FRONTEND_VERSION', defaultValue: "latest", description: 'Tag for the Frontend Docker image')
    }
        environment {
        APP_SERVER = "10.0.1.101" 
    }

    
    stages {
        stage('Trigger Downstream Pipelines') {
            parallel {
                stage('Trigger Backend Pipeline') {
                    steps {
                        build job: 'backend_pipeline', parameters: [string(name: 'VERSION', value: params.BACKEND_VERSION)], wait: true
                    }
                }
                stage('Trigger Frontend Pipeline') {
                    steps {
                        build job: 'frontend_pipeline', parameters: [string(name: 'VERSION', value: params.FRONTEND_VERSION)], wait: true
                    }
                }
            }
        }
        stage('Deploy to APP Server') {
            steps {
                script {
                    withCredentials([sshUserPrivateKey(credentialsId: 'appserverkey', keyFileVariable: 'SECURE_SSH_KEY', usernameVariable: 'SSH_USER')]) {
                        sh """
                chmod 400 "\$SECURE_SSH_KEY"

                # 2. Transfer BOTH files to the deployment target directory
                echo "Transferring orchestration assets..."
                scp -i "\$SECURE_SSH_KEY" -o StrictHostKeyChecking=no ../backend_pipeline/docker-compose-deploy.yaml ${SSH_USER}@${APP_SERVER}:~/docker-compose.yaml
                scp -i "\$SECURE_SSH_KEY" -o StrictHostKeyChecking=no .env ${SSH_USER}@${APP_SERVER}:~/.env

                # 3. Securely run docker compose down/up commands natively
                echo "Executing clean remote environment rollout..."
                ssh -i "\$SECURE_SSH_KEY" -o StrictHostKeyChecking=no ${SSH_USER}@${APP_SERVER} "
		    pwd
		    ls -la					
                    docker compose down
                    sleep 5
                    docker compose pull
                    docker compose up -d --remove-orphans
                "
            """
                    }
                }
            }
        }
    }
}