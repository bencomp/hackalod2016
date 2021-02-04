# Terminologie

Canvas: een pagina of "view" – voor ons een pagina in een boek
annotaties bepalen de link tussen afbeelding van pagina en canvas, maar ook meer in het algemeen links tussen content en aantekeningen/transcripties/etc.

annotaties worden gegroepeerd in annotation lists

Layer: groepering van annotation lists

- maken we een layer voor heeft-plaatje-annotaties?

# Algemeen toepasbare ideeën

- een vertaler van DIDL naar IIIF Manifesten
- annotations zijn voeding voor machine learning
    - zijn er patronen te ontdekken in de attributen van annotaties?
    - waar in boeken zitten plaatjes in het algemeen?
    - clustering toegepast op boeken met metadata en annotaties – komt er iets uit als genre+uitgever+jaar?


# Voorbereiding

- bij een afbeelding-URI geserveerd door een IIIF Image API service kan de base-URI van de afbeelding worden gelinkt met de `service`-property in het manifest
- houd de HTTP-logs goed bij om benodigde bandbreedte te zien (visualiseren?)

