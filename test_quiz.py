import json

filepath = 'c:/AIQUIZ/AIQUIZ-Godot/offline_bank.json'

with open(filepath, 'r', encoding='utf-8') as f:
    data = json.load(f)

total_questions = 0
errors = []
duplicates = 0
seen_questions = set()

for subject, grades in data.items():
    for grade, questions in grades.items():
        for i, q in enumerate(questions):
            total_questions += 1
            
            if 'q' not in q or not isinstance(q['q'], str) or not q['q'].strip():
                errors.append(f'{subject} - {grade} - Q{i}: Invalid question string.')
            else:
                if q['q'] in seen_questions:
                    duplicates += 1
                seen_questions.add(q['q'])
                
            if 'c' not in q or not isinstance(q['c'], list) or len(q['c']) < 2:
                errors.append(f'{subject} - {grade} - Q{i}: Invalid choices array.')
            
            if 'a' not in q or not isinstance(q['a'], int):
                errors.append(f'{subject} - {grade} - Q{i}: Answer index missing/invalid.')
            elif 'c' in q and isinstance(q['c'], list) and not (0 <= q['a'] < len(q['c'])):
                errors.append(f'{subject} - {grade} - Q{i}: Answer index out of bounds.')
                
            if 'exp' not in q or not isinstance(q['exp'], str):
                errors.append(f'{subject} - {grade} - Q{i}: Explanation missing.')
                
            if 't' not in q or not (isinstance(q['t'], float) or isinstance(q['t'], int)) or q['t'] <= 0:
                errors.append(f'{subject} - {grade} - Q{i}: Time limit missing or invalid.')

print(f'Total questions checked: {total_questions}')
print(f'Duplicate questions found: {duplicates}')
print(f'Total errors found: {len(errors)}')

if errors:
    print('Errors:')
    for e in errors[:20]:
        print(e)
