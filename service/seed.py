import os
import json
import datetime
from random import randrange, choice

from models.base import Base, engine
from sqlalchemy.orm import Session
from fastapi import Depends
from models import Employee, AuthEnd, Goal, GoalStatus, Comment

from faker import Faker

sess = Session(engine)
fake = Faker()

    
for file in os.listdir("seeds/employees"):
   with open(f"seeds/employees/{file}") as f:
        data = (json.load(f))
        for entry in data:
            employee = Employee(
               first_name=entry["firstName"],
               last_name=entry["lastName"],
               employee_id = entry["employeeId"],
               email=entry["email"],
               company_id=entry["companyId"],
               company_name=entry["companyName"],
               position_title=entry["positionTitle"],
               current = True,
               password=entry["password"],
               manager_id=f"{entry.get('managerId')}_{entry['companyId']}"
               )
            sess.add(employee)
            sess.commit()
            sess.refresh(employee)

            login = AuthEnd(
                username = entry["email"],
                password = entry["password"],
                employee_ref = employee.id
            )
            sess.add(login)
            sess.commit()

            tot_employees = sess.query(Employee).count()

            # seeding a random number of goals per user
            for i in range(randrange(10)):
                goal = Goal(
                    title = fake.text(),
                    description = fake.text(),
                    assignee_id = employee.id, status = choice(list(GoalStatus)),
                    created_at = datetime.datetime.today(),
                    start_date = datetime.datetime.today(),
                    end_date = datetime.datetime.today(),
                    created_by = randrange(tot_employees)
                )

                sess.add(goal)
                sess.commit()
                sess.refresh(goal)

                for j in range(randrange(4)):
                    comment = Comment(
                        created_at = datetime.datetime.today(),
                        employee_id = employee.id,
                        description = fake.text(),
                        goal_id = goal.id,
                    )

                    sess.add(comment)
                    sess.commit()

print("Seed Complete!")
